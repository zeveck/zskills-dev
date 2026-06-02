# Z Skills Workflows

This is a **recipes / playbook** doc: it shows how to chain Z Skills into
real end-to-end workflows. For what an individual skill does and its full
argument list, see the [per-skill reference](../skills/README.md).

## Philosophy

Z Skills favors **plan-driven development**: for anything bigger than a
one-line change, you draft a plan, review it adversarially, then execute it
phase by phase. **Verification happens at every step** — implementers run
tests, a fresh verifier subagent re-checks the work before it lands, and
nothing reaches `main` unverified.

How finished work reaches `main` is controlled by a **landing mode**, passed
as a positional token to most execution skills:

| Mode | Token | How it works |
|------|-------|--------------|
| Cherry-pick | *(default)* | Work in an auto-named worktree, cherry-pick to `main` |
| PR | `pr` | Work in a named worktree, push the branch, open a PR |
| Direct | `direct` | Work directly on `main`, no landing step |

> **Argument syntax.** User-facing skills take **positional tokens** —
> `auto`, `pr`, `direct`, `finish` — *not* `--flags`. (For example:
> `/run-plan docs/plans/X.md finish auto pr`.) The dashed `--auto` form
> belongs only to the internal `/land-pr` helper that these skills dispatch
> for you; you should never type it yourself.

In `main_protected: true` projects, agents cannot commit or push directly to
`main`, so use `pr` mode (or a worktree). Add `auto` to opt into auto-merge
once CI is green.

---

## 1. Plan-driven feature

**When:** You have a goal and want a reviewed plan before any code is written.

```text
/draft-plan <goal>
/run-plan docs/plans/<file>.md finish auto
```

- `/draft-plan` researches the goal and runs iterative adversarial review,
  emitting a plan file under `docs/plans/`. This catches design flaws before
  they cost you commits. Add `brainstorm` for an interactive design dialogue
  before research, or `quiz` for an interactive requirements interview that
  elicits intent and scope before research.
- `/run-plan` executes that plan. `finish` runs **all** phases (not just the
  next one) and `auto` lets it land each phase autonomously, so you can walk
  away. Drop `finish auto` to step through one phase at a time.

## 2. Plan with test specs

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

## 3. Big goal decomposition

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

## 4. Mid-flight plan drift

**When:** A plan is partway executed and reality has diverged from the spec.

```text
/refine-plan docs/plans/<file>.md
/run-plan docs/plans/<file>.md finish auto
```

- `/refine-plan` reconciles the plan against the work already completed,
  rewriting remaining phases to match current reality instead of the stale
  original design.
- Resume `/run-plan` to execute the corrected remaining phases.

## 5. Backlog bug sprint

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

## 6. Unclear bug → root cause

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

## 7. Small ad-hoc change

**When:** A one-commit change you can describe directly, no plan needed.

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

**When:** You want to find test gaps before they bite, or verify UI behavior
in a real browser.

```text
/qe-audit
/manual-testing
```

- `/qe-audit` proactively scans the repo for test-coverage gaps and likely
  bugs and **files GitHub issues** — it generates work, where
  `/verify-changes` only gates your current changes.
- `/manual-testing` gives browser-based verification recipes (driven by
  `playwright-cli`) for confirming user-facing behavior with real
  mouse/keyboard events.

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
