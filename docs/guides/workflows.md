# Z Skills Workflows

This is a **recipes / playbook** doc: it shows how to chain Z Skills into
real end-to-end workflows. For what an individual skill does on its own —
its flow diagram, full description, and argument list — see the
[Z Skills Reference](../skills/README.md), where every skill's page now
opens with its flow.

## 1. Everyday change — just `/do` it

<details class="flow-cmd">
<summary><code>/do</code> → PR</summary>

<div class="flow">
<div class="flow-step"><p><strong>You</strong> describe the change — its approach is already clear</p></div>
<div class="flow-step"><p><strong><code>/do</code></strong> isolates the work in a worktree and lands it as a PR</p></div>
</div>

</details>

**When:** Any change you can describe whose approach is clear — a doc edit, a
bug fix, a refactor, a new UI element, a content update. This is the workhorse
you reach for most; most "just ask Claude" work runs through it. If the work
has unknowns, turns out to be complicated, or would benefit from deeper review
or staging into phases, reach for `/draft-plan` instead.

```text
/do "<task>"             # the everyday workhorse; lands per your configured mode
```

- "Lightweight" means **no staged phases and no open design** — *not* "small."
  A wide but settled change is still a `/do`; reach for `/draft-plan` only when
  the design is open or the work needs to be staged into ordered phases.
- How the change reaches `main` — a worktree and cherry-pick, a PR, or direct on
  `main` — follows your configured landing mode; see
  [Configuring zskills](zskills-config.md).

## 2. Plan-driven feature

<details class="flow-cmd">
<summary><code>/draft-plan</code> → <code>/run-plan</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/draft-plan</code></strong> researches the goal and writes a reviewed plan file</p></div>
<div class="flow-step"><p><strong><code>/run-plan finish auto</code></strong> executes every phase and lands them autonomously</p></div>
</div>

</details>

**When:** You have a goal and want a reviewed plan before any code is written.

```text
/draft-plan <goal>
/run-plan docs/plans/<file>.md finish auto
```

- `/draft-plan` researches the goal and runs repeated rounds of critical
  review, writing a plan file under `docs/plans/`. This catches design flaws
  before they cost you commits. Add `brainstorm` for an interactive design
  dialogue before research, or `quiz` for an interactive requirements
  interview that draws out intent and scope before research.
- `/run-plan` executes that plan. `finish` runs **all** phases (not just the
  next one) and `auto` lets it land each phase autonomously, so you can walk
  away. Drop `finish auto` to step through one phase at a time.

## 3. Plan with test specs

<details class="flow-cmd">
<summary><code>/draft-plan</code> → <code>/draft-tests</code> → <code>/run-plan</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/draft-plan</code></strong> researches the goal and writes a reviewed plan file</p></div>
<div class="flow-step"><p><strong><code>/draft-tests</code></strong> designs test specs into each pending phase</p></div>
<div class="flow-step"><p><strong><code>/run-plan finish auto</code></strong> executes the phases, tests included</p></div>
</div>

</details>

**When:** The work is test-critical and you want a dedicated QE pass that
designs detailed test specs into the plan — going beyond the testable
acceptance criteria `/draft-plan` already writes.

```text
/draft-plan <goal>
/draft-tests docs/plans/<file>.md
/run-plan docs/plans/<file>.md finish auto
```

- `/draft-plan` already gives every phase testable acceptance criteria;
  `/draft-tests` runs a separate senior-QE review loop that designs detailed
  test specs — concrete cases and edge cases — into each pending phase, so the
  implementing agent has them spelled out rather than improvising.
- `/run-plan` then executes those phases with the specs riding along inside
  them; there's no separate test document to maintain.

## 4. Big goal decomposition

<details class="flow-cmd">
<summary><code>/research-and-plan</code> → <code>/run-plan</code> — review the split first</summary>

<div class="flow">
<div class="flow-step"><p><strong>You</strong> describe the broad goal</p></div>
<div class="flow-step"><p><strong><code>/research-and-plan</code></strong> decomposes it into sub-plans and stops for your review</p></div>
<div class="flow-step"><p>You review the meta-plan, then <strong><code>/run-plan finish auto</code></strong> executes each sub-plan in turn</p></div>
</div>

</details>

<details class="flow-cmd">
<summary><code>/research-and-go</code> — the same, bundled and hands-off</summary>

<div class="flow">
<div class="flow-step"><p><strong>You</strong> describe the broad goal</p></div>
<div class="flow-step"><p><strong><code>/research-and-go</code></strong> decomposes it, drafts every sub-plan, and runs them all — no review stop</p></div>
<div class="flow-step optional"><p>It's <code>/research-and-plan</code> + <code>/run-plan</code> in one pass, so it takes some optimism — reach for it once you trust the setup and can walk away</p></div>
</div>

</details>

**When:** The goal is too large for one plan and decomposes into several
dependent sub-plans.

```text
/research-and-plan <goal>      # draft a meta-plan of sub-plans, then stop for review
# review the meta-plan, then run each sub-plan:
/run-plan docs/plans/<sub-plan>.md finish auto
```

Or, to draft **and** execute everything in one autonomous pass:

```text
/research-and-go <goal>
```

- `/research-and-plan` researches the domain, identifies sub-problems and
  their dependencies, and produces a meta-plan whose phases each delegate to
  `/run-plan` — then stops so you can review before commit-volume work begins.
- `/research-and-go` is `/research-and-plan` and `/run-plan` bundled into one
  command: same drafting machinery, but it continues straight into execution
  with no review checkpoint. That takes some optimism — reach for it once you
  trust the setup and have genuinely said "walk away."

## 5. Reconcile a plan with reality

<details class="flow-cmd">
<summary><code>/refine-plan</code> → <code>/run-plan</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/refine-plan</code></strong> reconciles the plan against current reality — the codebase, plus any completed phases</p></div>
<div class="flow-step"><p><strong><code>/run-plan finish auto</code></strong> executes the corrected phases</p></div>
</div>

</details>

**When:** You have an existing plan that no longer matches reality — maybe it
was partly executed and the work diverged, or it was drafted a while ago and the
codebase has since moved on. You want to build on the plan you have, not redraft
it.

```text
/refine-plan docs/plans/<file>.md
/run-plan docs/plans/<file>.md finish auto
```

- `/refine-plan` reviews the plan against what actually exists now — the
  codebase, plus any completed phases — and rewrites the **remaining** phases to
  match, keeping completed phases and the plan's structure intact instead of
  starting over.
- It's the *build on what you have* counterpart to `/draft-plan`: `/draft-plan`
  drafts a fresh plan from the goal (even when you hand it an existing document),
  while `/refine-plan` keeps and updates the document you already have. Reach for
  it when you have a `/run-plan`-shaped plan you want to sync, not replace.
- Resume `/run-plan` to execute the corrected phases.

## 6. Proactive coverage

<details class="flow-cmd">
<summary><code>/qe-audit</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/qe-audit</code></strong> scans recent commits for risky changes</p></div>
<div class="flow-step"><p><strong>Audit subagents</strong> comb them in parallel with fresh eyes</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> re-verifies each finding and files GitHub issues with repro recipes</p></div>
</div>

</details>

**When:** You want to find test gaps before they bite.

```text
/qe-audit
```

- `/qe-audit` proactively scans the repo for test-coverage gaps and likely
  bugs and **files GitHub issues** — it generates work, where
  `/verify-changes` only gates your current changes.
- `/manual-testing` is an internal helper you don't run directly —
  `/verify-changes` dispatches it to verify UI behavior with real
  mouse/keyboard events (`playwright-cli`).

## 7. Backlog bug sprint

<details class="flow-cmd">
<summary><code>/fix-issues</code> → <code>/fix-report</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/fix-issues N</code></strong> fixes up to N issues, each in its own worktree</p></div>
<div class="flow-step"><p><strong><code>/fix-report</code></strong> reviews the sprint, lands the fixes, and closes the issues</p></div>
<div class="flow-step optional"><p>With <strong>auto</strong> the sprint lands and merges each fix itself — <code>/fix-report</code> is for the non-auto path</p></div>
</div>

</details>

**When:** You have several small bugs or issues to clear in one batch.

```text
/fix-issues 5 pr auto
/fix-report
```

- `/fix-issues N` runs a batch sprint, fixing up to `N` issues each in its own
  worktree. Add `pr` to land each via PR and `auto` for auto-merge; omit them
  to use the default cherry-pick mode.
- `/fix-report` walks the sprint results, gates landing on your review of each
  manual verification, lands the fixes, and closes the GitHub issues.
- `/fix-issues` is schedulable — `/fix-issues 1 every 60m auto` clears one issue
  an hour, unattended. See [Run something on a schedule](#12-run-something-on-a-schedule).

## 8. Unclear bug → root cause

<details class="flow-cmd">
<summary><code>/investigate</code> → <code>/do</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/investigate</code></strong> proves the root cause and leaves a regression test</p></div>
<div class="flow-step"><p><strong><code>/do</code></strong> ships the now-known fix as a PR</p></div>
</div>

</details>

**When:** Something is broken but the root cause is not yet proven.

```text
/investigate <description or #issue>
/do "fix <root cause>" pr
```

- `/investigate` does deep root-cause debugging: it proves *why* the bug
  happens and produces a regression test, rather than guessing at a fix.
- Once the root cause is known, ship the fix with `/do` — the fix is now a
  known change, not an investigation.

## 9. Verify changes

<details class="flow-cmd">
<summary><code>/verify-changes</code> — review a feature end to end</summary>

<div class="flow">
<div class="flow-step"><p>A <strong>fresh verifier subagent</strong> reviews the diff and audits test coverage — fresh eyes on the actual code, not session memory</p></div>
<div class="flow-step"><p>The <strong>original agent</strong> runs the full test suite</p></div>
<div class="flow-step"><p>It dispatches <code>/manual-testing</code> for a real browser pass on UI changes</p></div>
<div class="flow-step"><p>It fixes what surfaces and re-verifies, looping until clean</p></div>
<div class="flow-step"><p>It reports findings and recommendations</p></div>
</div>

</details>

**When:** You want to confirm a feature actually works — covered by tests,
passing them, and behaving correctly in the UI. This is a **feature review**,
not a code review: the question is "does this work and is it verified," not "is
the code tidy."

```text
/verify-changes              # all uncommitted changes in the working tree (default)
/verify-changes branch       # every commit on the current branch vs main
/verify-changes last 3       # just the last 3 commits — recent or just-landed work
```

- `/verify-changes` reviews the diff, audits test coverage, runs the suite, and
  drives the UI with `/manual-testing` where relevant — then fixes what it finds
  and re-verifies until clean.
- Point it at the scope you care about: the default checks current uncommitted
  work; `worktree` checks a worktree against its base; `branch` checks the whole
  branch; `last [N]` checks recent (or just-landed) commits. Run it before you
  land to gate the work, or right after to confirm what shipped.
- The review runs with **fresh eyes** — when it can dispatch, it hands the diff
  and coverage review to a separate verifier subagent that reads the actual code
  rather than trusting memory of what changed. That independence is what gives
  the verdict weight: a real check, not a rubber stamp of what you think you did.

## 10. Post-merge cleanup

<details class="flow-cmd">
<summary><code>/cleanup-merged</code></summary>

<div class="flow">
<div class="flow-step"><p>The <strong>agent</strong> fetches and prunes the remote-tracking branches GitHub has already deleted</p></div>
<div class="flow-step"><p>If you're on a now-merged branch, it switches to main and pulls</p></div>
<div class="flow-step"><p>It removes the worktrees held by merged branches (clean ones only)</p></div>
<div class="flow-step"><p>It deletes the merged local branches — and remote ones too, with <code>remote</code> / <code>all</code></p></div>
</div>

</details>

**When:** Some of your PRs have merged on GitHub and you want to clear out the
branches and worktrees they left behind.

```text
/cleanup-merged              # preview what would be removed (local)
/cleanup-merged apply        # remove merged local branches + their worktrees
/cleanup-merged all apply    # also delete the merged branches on the remote
```

- `/cleanup-merged` is mostly a **branch + worktree sweeper**: it removes the
  worktrees held by merged branches (skipping any that are dirty) and deletes the
  merged branches themselves. Switching to `main` and pulling is just the part
  that gets you off a branch that's about to be deleted.
- **Preview by default** — a bare invocation shows what it *would* remove; add
  `apply` to act. `local` (default) / `remote` / `all` pick the scope.
- It never deletes a branch with unpushed commits, never removes a dirty
  worktree, and never touches protected branches from your config.

## 11. Status & monitoring

<details class="flow-cmd">
<summary><code>/session-report</code> · <code>/briefing</code> · <code>/plans</code> · <code>/zskills-dashboard</code></summary>

<div class="flow">
<div class="flow-step"><p><strong><code>/session-report</code></strong> — what this session actually shipped vs. intended</p></div>
<div class="flow-step"><p><strong><code>/briefing</code></strong> — project status: commits, worktrees, open checkboxes</p></div>
<div class="flow-step"><p><strong><code>/plans</code></strong> — every plan's status and the next ready one</p></div>
<div class="flow-step"><p><strong><code>/zskills-dashboard</code></strong> — local web UI for plans, issues, and tracking</p></div>
</div>

</details>

**When:** You want to see where this session, the project, or your plans stand.

```text
/session-report          # audit what THIS session actually shipped vs. intended
/session-report handoff  # persist a durable, forward-looking end-of-session hand-off
/briefing                # project status: commits, worktrees, open checkboxes
/plans                   # plan dashboard: statuses, next ready plan
/zskills-dashboard       # local web UI for plans, issues, and tracking
```

- `/session-report` reconciles what the current session *intended* against what
  actually landed — checked against git, PRs, and plans, not memory. Add
  `handoff` to instead write a durable, forward-looking hand-off that you or the
  next session can pick up from.
- `/briefing` summarizes current project state at a glance.
- `/plans` shows every plan's status and points you at the next ready one.
- `/zskills-dashboard` serves a local web dashboard for plans, issues, and
  tracking markers.

---

## 12. Run something on a schedule

<details class="flow-cmd">
<summary><strong><code>every SCHEDULE</code></strong> — the shared scheduling mechanic</summary>

<div class="flow">
<div class="flow-step"><p>Add <strong>every 30m</strong> (or any interval) to any of the five schedulable skills</p></div>
<div class="flow-step"><p>A self-perpetuating cron is registered</p></div>
<div class="flow-step"><p>Each fire runs the flow and re-registers the next one</p></div>
<div class="flow-step"><p>Manage it with <strong>stop</strong> or <strong>next</strong></p></div>
</div>

</details>

**When:** You want a skill to run unattended on a recurring interval — clear new
issues as they arrive, re-audit after each batch of work, or drain the plan queue
through the day.

Five skills take `every SCHEDULE` — `/do`, `/fix-issues`, `/run-plan`,
`/qe-audit`, and `/work-on-plans`. Append the interval to any of them:

```text
/fix-issues 1 every 60m auto                 # fix one issue an hour, landing each itself
/qe-audit every 6h                           # re-audit the repo every six hours
/work-on-plans every 4h                      # drain the ready-plan queue through the day
/do "check examples for broken links" every 12h now   # run now, then every 12h
```

- Add `now` to also run once immediately; pair with `auto` so scheduled fires
  land without waiting for you.
- The schedule is **session-scoped** — it ends when the session does.
- `<skill> stop` cancels the cron; `<skill> next` shows its next fire time.
- For unattended runs, set `logging.dir` so you have a transcript to review
  afterward — see [Inspecting & monitoring](inspecting-and-monitoring.md).

---

## See also

- [Per-skill reference](../skills/README.md) — every skill with its
  description and full argument syntax.
