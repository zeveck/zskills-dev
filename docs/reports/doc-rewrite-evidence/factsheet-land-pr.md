# Fact sheet — docs/skills/land-pr.md

Every factual claim in the rewritten `docs/skills/land-pr.md` traced to a
verbatim line in `skills/land-pr/SKILL.md` (the ground-truth source). Source
read in full; the load-bearing claims all live in the frontmatter + opening
prose (lines 1–39).

Source version at time of writing: `metadata.version: "2026.06.01+979c6f"`
(`skills/land-pr/SKILL.md:7`).

---

## Lead framing — "internal helper, don't call it directly"

**Doc sentence:** "`/land-pr` is marked `user-invocable: false`, which means
typing it at the slash prompt gets you nowhere."

- `skills/land-pr/SKILL.md:3`: `user-invocable: false`
- `skills/land-pr/SKILL.md:39`: `"This skill carries `user-invocable: false` for a reason — the slash runtime will not dispatch it from a human-typed slash command in any useful way."`

**Doc sentence:** "Other skills dispatch it behind the scenes when they need to
ship a branch."

- `skills/land-pr/SKILL.md:18-19`: `"`/land-pr` is a helper, not a user-facing command: the API requires `--body-file` and `--result-file`, both of which only make sense when a caller has set them up."`

---

## "To land a branch as a PR, use /commit pr"

**Doc sentence:** "To land a branch as a PR, use `/commit pr` ... `/commit pr`
figures out the title and body, then runs `/land-pr` for you with the right
setup."

- `skills/land-pr/SKILL.md:19-23`: `"Users wanting to ship an existing branch should use `/commit pr`, which dispatches `/land-pr` internally with the right arguments."`
- `skills/land-pr/SKILL.md:4` (description): `"Not for direct slash invocation — humans should use /commit pr instead."`

---

## "What it does" — behavior paragraph

**Doc sentence:** "it rebases the branch onto `main`, pushes it, creates the PR
(or picks up an existing one), watches CI until the checks finish, and — when
the caller asked to auto-merge — merges it and brings your local `main` up to
date."

- `skills/land-pr/SKILL.md:12-13`: `"`/land-pr` owns the rebase → push → create-or-detect → monitor → merge sequence for a feature branch that is already in a presentable state."`
- `skills/land-pr/SKILL.md:13` (rebase onto main, default base): the skill body documents `BASE_BRANCH="main"` (`skills/land-pr/SKILL.md:76`) and Step 3 "Run `pr-rebase.sh` against the configured base branch" (`skills/land-pr/SKILL.md:264`).
- create-or-detect-existing-PR: Step 4 header `"Push and create-or-detect PR"` (`skills/land-pr/SKILL.md:317`); frontmatter description `"create-or-detect PR"` (`skills/land-pr/SKILL.md:4`).
- watch CI: Step 6 `"Monitor CI"` (`skills/land-pr/SKILL.md:367`); description `"poll CI"` (`skills/land-pr/SKILL.md:4`).
- merge only when caller asked to auto-merge: Step 7 header `"Merge (gated on `--auto`)"` (`skills/land-pr/SKILL.md:619`); description `"optional auto-merge"` (`skills/land-pr/SKILL.md:4`).
- brings local main up to date: Step 7b `"Fast-forward local main after successful merge"` (`skills/land-pr/SKILL.md:888`); `"refresh local `$BASE_BRANCH` so subsequent worktree creations and any consumer of `main` see ground truth"` (`skills/land-pr/SKILL.md:890-892`).

**Doc sentence:** "If `main` moves while CI is running, `/land-pr` rebases and
re-checks on its own so the PR doesn't get stuck waiting."

- `skills/land-pr/SKILL.md:413` (Step 6b header): `"Auto-rebase BEHIND PRs post-CI-green (Issue #266)"`
- `skills/land-pr/SKILL.md:414-416`: `"After Step 6 returns `CI_STATUS=pass`, the PR's `mergeStateStatus` may be `BEHIND` because `origin/$BASE_BRANCH` advanced while CI was running (a sibling PR landed)."`
- `skills/land-pr/SKILL.md:423-426`: `"This step closes that loop: detect BEHIND, rebase locally onto current `origin/$BASE_BRANCH`, force-push with lease, re-poll CI, re-check `mergeStateStatus`."`

**Doc sentence:** "You don't see any of this directly; you see the finished PR
... reported back by whichever skill you ran."

- `skills/land-pr/SKILL.md:38-39`: `"When this skill returns to the orchestrator ... the orchestrator typically composes a user-facing summary of the landing outcome ... just report the PR URL + merge status."`

---

## "Who runs it for you" — the eight callers

**Doc claim:** Eight skills dispatch `/land-pr`: `/commit pr`, `/do pr`,
`/quickfix`, `/fix-issues pr`, `/run-plan`, `/draft-plan`, `/refine-plan`,
`/draft-tests`.

- `skills/land-pr/SKILL.md:14-19`: `"Eight callers dispatch into this skill via the Skill tool: the five implementation callers (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`) and the three drafting callers (`/draft-plan`, `/refine-plan`, `/draft-tests` ...)."`
- `skills/land-pr/SKILL.md:4` (description): `"Dispatched via the Skill tool by /run-plan, /commit pr, /do pr, /fix-issues pr, /quickfix, /draft-plan, /refine-plan, /draft-tests"`
- `skills/land-pr/SKILL.md:39`: `"The other 7 caller skills (`/run-plan`, `/do pr`, `/fix-issues pr`, `/quickfix`, `/draft-plan`, `/refine-plan`, `/draft-tests`) all dispatch `/land-pr` internally"` (the 7 + `/commit pr` = 8).

Per-caller one-line notes are drawn from `COMPANIONS.md` (R6 companion graph,
`land-pr` row, line 86) and CLAUDE.md "Which skill for which input", not invented:
- `/commit pr` "the most direct way" — COMPANIONS.md line 77 `"`commit pr` dispatches `/land-pr`; peers call it to land."`
- `/do pr` "isolated worktree" — CLAUDE.md decision table (`/do` = worktree isolation).
- `/quickfix` "minimal-ceremony one-commit PR" — CLAUDE.md execution-modes table.
- `/fix-issues pr` "work through a backlog of issues" — COMPANIONS.md line 83.
- `/run-plan` "multi-phase plan" — COMPANIONS.md line 94 `"Executes a drafted plan; lands phases via `/land-pr`"`.
- `/draft-plan`, `/refine-plan`, `/draft-tests` (drafting callers) — `skills/land-pr/SKILL.md:16-19` `"the three drafting callers ... so their worktree-committed plan/spec files reach main."`

---

## Companion / "See also"

Drawn from `COMPANIONS.md` `land-pr` row (line 86): companions are `commit`,
`do`, `quickfix`, `fix-issues`, `run-plan`, `draft-plan`, `refine-plan`,
`research-and-plan`, `draft-tests`; relationship: **Internal
(`user-invocable: false`). Dispatched BY its callers; never typed directly.**
The "See also" links `/commit` and the workflows guide, consistent with the
graph and with the prior doc's See-also section.

---

## Deliberately DROPPED (R5 — no internals voice)

These appeared in the prior doc and are removed because a user never observes them:

- The 13 result-`STATUS` codes (`merged`/`created`/`monitored`/`push-failed`/
  `rebase-conflict`/`create-failed`/`monitor-failed`/`merge-failed`/
  `rebase-failed`/`behind-thrash`/`auto-rebase-conflict`/`auto-rebase-blocked`)
  — internal hand-off enum (`skills/land-pr/SKILL.md:166`).
- `--result-file` / `--body-file` / `--branch` / `--title` and the argument
  validation gates — caller-supplied plumbing (`skills/land-pr/SKILL.md:5`,
  `:50-136`); a user never types these.
- The `.landed` schema, the allow-list result parser, sidecar files, the
  3-iteration cap, `mergeStateStatus` states — implementation internals
  (`skills/land-pr/SKILL.md:138-208`, `:439-454`).
- "What happens if a user types `/land-pr`?" section with the
  `ERROR: /land-pr requires --branch` walkthrough — replaced by the plain
  lead framing "typing it gets you nowhere" (the error text is implementer
  detail, not user-actionable).

---

## Banned-term check

`grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/skills/land-pr.md`
expected to return no hits (no `materialiser`, `sentinel`, `atomic`, `Phase N`,
`WI N.N`, `subagent_type`, `Tier`, design-decision `D[0-9]+`, etc. in the
rewritten prose). `user-invocable: false` is retained deliberately — it names a
real frontmatter state the doc explains in plain words and is the exact reason
the user can't type the command; it is not on the banned list.
