# Z Skills Workflows

This is a **recipes / playbook** doc: it shows how to chain Z Skills into
real end-to-end workflows. For what an individual skill does and its full
argument list, see the [per-skill reference](../skills/README.md).

## Philosophy

Z Skills matches the skill to the work — not the other way around. The
everyday workhorse is `/do` (with its co-equal peer `/quickfix`): when you
can describe the change and its approach is clear, `/do` it — whatever the
size, from a typo to a wide refactor to plumbing a new UI element. A backlog
of bugs to clear runs through `/fix-issues`. Reach for `/draft-plan` **freely**
— lean toward it on a genuine toss-up — whenever the work has open design to
work out or needs to be staged into ordered phases. A broad goal that splits
into several dependent sub-plans gets `/research-and-plan`.

The axis is **design-depth / staging, not file-count**: thirty files changed
by one settled approach is still a `/do`; one change with unresolved design is
a `/draft-plan`.

**Your changes are checked before they land**, whichever skill you pick:
tests run, a separate review pass re-checks the work, and nothing reaches
`main` unchecked. The skill choice governs how much *ceremony* the work
goes through; the checking is constant.

Landing mode (cherry-pick / locked-main-pr / direct) is install-time
configuration — covered in
[Installing zskills → Landing mode](installing-zskills.md#landing-mode).
The workflow snippets below pass `pr` or `direct` as a positional override
when needed; otherwise the configured default applies.

> **Argument syntax.** Most arguments you type are **positional tokens** —
> mode/verb words like `auto`, `pr`, `direct`, `finish` with no dashes.
> (For example: `/run-plan docs/plans/X.md finish auto pr`.) A few skills
> also take dashed flags, which are reserved for overriding a safety gate:
> `--force` (on `/do`, `/quickfix`, `/work-on-plans`, `/cleanup-merged`)
> skips the triage and review step, and `--rounds N` (on `/do`) sets how
> many review-and-refine cycles run. The one dashed flag you do **not**
> type is `--auto`: that form belongs to the internal `/land-pr` helper
> these skills dispatch for you. To auto-merge, pass the positional `auto`
> token instead.

---

## 1. Everyday change — just `/do` it

**When:** Any change you can describe whose approach is clear — a doc edit, a
bug fix, a refactor, a new UI element, a content update. This is the workhorse
you reach for most; most "just ask Claude" work runs through it.

```text
/do "<task>" pr          # worktree-isolated; required when main is protected
# or, only when main is NOT protected:
/quickfix "<task>"       # in-place on main, no worktree
```

- `/do` and `/quickfix` are **peers, not tiers** — same lifecycle (triage →
  review → commit → PR → land) and same one-commit-PR shape. The only
  difference is *where the work tree lives*.
- Choose by **project policy, not task size**: `main_protected: true`
  projects must use `/do` (it isolates work in a worktree); `/quickfix` edits
  in place on `main` and is valid only when `main_protected: false`.
- "Lightweight" means **no staged phases and no open design** — *not* "small."
  A wide but settled change is still a `/do`; reach for `/draft-plan` only when
  the design is open or the work needs to be staged into ordered phases.

## 2. Plan-driven feature

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

**When:** You want test coverage designed into the plan up front, not bolted on.

```text
/draft-plan <goal>
/draft-tests docs/plans/<file>.md
/run-plan docs/plans/<file>.md finish auto
```

- `/draft-tests` reads an existing plan and writes test specifications into
  its phases, so each phase ships with its tests defined rather than improvised.
- `/run-plan` then executes phases whose acceptance criteria already include
  those tests.
- For an even more grounded plan, pre-seed `/draft-plan` with `brainstorm`
  (design dialogue) or `quiz` (requirements interview) before `/draft-tests`
  appends test specs.

## 4. Big goal decomposition

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
- `/research-and-go` uses the same drafting machinery but continues straight
  into execution. Use it when you've said "walk away."

## 5. Mid-flight plan drift

**When:** A plan is partway executed and reality has diverged from the spec.

```text
/refine-plan docs/plans/<file>.md
/run-plan docs/plans/<file>.md finish auto
```

- `/refine-plan` reconciles the plan against the work already completed,
  rewriting remaining phases to match current reality instead of the stale
  original design.
- Resume `/run-plan` to execute the corrected remaining phases.

## 6. Backlog bug sprint

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

## 7. Unclear bug → root cause

**When:** Something is broken but the root cause is not yet proven.

```text
/investigate <description or #issue>
/do "fix <root cause>" pr        # or: /quickfix "fix <root cause>"
```

- `/investigate` does deep root-cause debugging: it proves *why* the bug
  happens and produces a regression test, rather than guessing at a fix.
- Once the root cause is known, ship the fix with `/do pr` (worktree) or
  `/quickfix` (no worktree) — the fix is now a known change, not an
  investigation.

## 8. Pre-commit quality gate

**When:** You have changes ready and want them verified before they land.

```text
/verify-changes
/commit pr
```

- `/verify-changes` reviews your recent changes end to end: diffs, test
  coverage, a real test run, and manual UI checks where relevant. It gates the
  commit — fix what it surfaces before proceeding.
- `/commit pr` commits the work and opens a PR by dispatching `/land-pr` for
  you (proper rebase, CI monitoring, fix-cycle on failure). Add `auto` for
  auto-merge.

## 9. Post-merge cleanup

**When:** A PR has merged on GitHub and your local clone is behind.

```text
/cleanup-merged
```

- `/cleanup-merged` checks out `main`, pulls, and deletes merged feature
  branches so your local clone matches the remote. It's safe to run anytime
  and bails on a dirty tree.

## 10. Proactive coverage

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

## 11. Status & monitoring

**When:** You want to see where the project, plans, or this session stand.

```text
/briefing             # project status: commits, worktrees, open checkboxes
/plans                # plan dashboard: statuses, next ready plan
/zskills-dashboard    # local web UI for plans, issues, and tracking
/session-report       # audit what THIS session actually shipped vs. intended
```

- `/briefing` summarizes current project state at a glance.
- `/plans` shows every plan's status and points you at the next ready one.
- `/zskills-dashboard` serves a local web dashboard for plans, issues, and
  tracking markers.
- `/session-report` reconciles what the current session intended against what
  actually landed.

---

## See also

- [Per-skill reference](../skills/README.md) — every skill with its
  description and full argument syntax.
