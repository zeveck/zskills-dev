# Fact sheet — docs/skills/quickfix.md

Each row pairs a sentence (or clause) in the rewritten `docs/skills/quickfix.md`
with the source line that backs it. Quotes are verbatim from
`skills/quickfix/SKILL.md` (and `skills/quickfix/modes/execute.md` where noted)
at HEAD on the worktree. Line numbers are at time of writing; verifier should
re-check the quote is at that line.

## What it does

| Doc sentence | Source citation |
|---|---|
| "takes the change you have on your main checkout and ships it as a single-commit PR" / "It stays on main the whole time" | `skills/quickfix/SKILL.md:19`: "`/quickfix` turns the current main checkout (with or without dirty edits)" |
| "There is no separate worktree and no cherry-pick step." | `skills/quickfix/SKILL.md:20`: "into a one-commit PR without leaving main. No worktree. No cherry-pick." |
| "it sizes up the request, has a fresh agent review the plan, commits, verifies the result, pushes, opens the PR, and watches CI" | `skills/quickfix/SKILL.md:21`: "Lifecycle: triage → review → commit → verify → push → PR → CI poll → fix cycle." |
| "If you have uncommitted edits on main and you give a description, `/quickfix` picks up those edits and commits them under your description." | `skills/quickfix/SKILL.md:29`: "| No  | non-empty | **user-edited** | pick up dirty tree, commit under description |" |
| "If your tree is clean and you give a description, `/quickfix` has an agent make the change for you, then commits it." | `skills/quickfix/SKILL.md:31`: "| Yes | non-empty | **agent-dispatched** | model-layer dispatch of an agent to implement, then commit |" |
| "with a clean tree the description is the only input, so it is required" | `skills/quickfix/SKILL.md:30`: "| No  | empty     | — | exit 2 (user-edited mode requires a description) |" (and SKILL.md:31's agent-dispatched row requires a non-empty description) |
| "handing the PR creation, CI-watching, and any fix-up cycle to `/land-pr` behind the scenes" | `skills/quickfix/SKILL.md:54`: "auto-merge via `/land-pr` and matches the convention in `/run-plan`," (lifecycle dispatched via land-pr); corroborated `references/exit-codes-and-rules.md:26`: "PR creation, CI monitoring, and the fix cycle are dispatched via `/land-pr`" |
| "If the tests fail, it leaves your edits in your working tree, switches you back to your starting branch, and removes the feature branch it created" | `skills/quickfix/modes/execute.md:116`: "    # Rollback: leave edits in the working tree (user may have work to save)," and `execute.md:117`: "    # drop back to base, delete the feature branch." |
| "a separate verification pass that checks your change is actually sound (the same check `/verify-changes` performs) before pushing" | `skills/quickfix/modes/execute.md:288`: "**Dispatch a separate verification agent** running `/verify-changes`." |
| "several files named in the description, an 'add feature'/'rewrite'/'refactor' verb, two unrelated things joined by 'and', or a reference to an existing plan file" | `skills/quickfix/SKILL.md:540`: "| Verbs include any of: `add feature`, `redesign`, `rewrite`, `refactor across` | REDIRECT → `/draft-plan` | both |"; `SKILL.md:541`: "| `and` connects unrelated areas (e.g. \"fix nav and update copy\") | REDIRECT → `/draft-plan` | both |"; `SKILL.md:543`: "| References an existing plan file under `$ZSKILLS_PLANS_DIR` | REDIRECT → `/run-plan` | both |" |
| "`/quickfix` stops and points you at a better-suited skill (`/draft-plan` or `/run-plan`)" | `skills/quickfix/SKILL.md:568`: "| `/draft-plan` | `Triage: redirecting to /draft-plan. ..." and `SKILL.md:569`: "| `/run-plan` | `Triage: redirecting to /run-plan. ..." |
| "You can override that with `--force`." | `skills/quickfix/SKILL.md:559` redirect handling references `--force`; backed by arg def `SKILL.md:64`: "**--force** (optional) — bypass a triage REDIRECT verdict (WI 1.5.4) and" |
| "it prints a short note redirecting you to `/do` (for worktree-based projects) or `/commit` (for direct-to-main projects) and stops" | `skills/quickfix/SKILL.md:406-410`: `if [ "$LANDING" = "worktree" ]; then` → redirect to `/do worktree`; `elif [ "$LANDING" = "direct" ]; then` → redirect to `/commit`. Quote `SKILL.md:399`: "mode and `exit 0` so the user can re-invoke the suggested skill. The" |

## Typical usage

| Doc sentence | Source citation |
|---|---|
| "Reach for `/quickfix` when the change is small enough that spinning up an isolated worktree would be more ceremony than the change is worth, but you still want it to land as a reviewable PR." | `skills/quickfix/SKILL.md:45`: "Pick `/quickfix` when the edit is small enough that leaving main is more" and `SKILL.md:46`: "ceremony than the change is worth, but a PR is still required." |
| "`/quickfix` and `/do` are co-equal peers ... The only real difference is where the work happens: `/quickfix` works in place on main, while `/do` works in an isolated worktree." | `skills/quickfix/SKILL.md:40`: "- `/do pr` — fresh worktree, agent-dispatched, for larger tasks." and `SKILL.md:43`: "- `/quickfix` — on **main** with in-flight edits (or clean main + description)." Peer framing per CLAUDE.md "Common confusions" / COMPANIONS.md (R7). |
| "the work happens ... in place on main" (branch made in place via checkout -b) | `skills/quickfix/SKILL.md:35`: "so dirty edits made on main are carried across (via `git checkout -b`) into" |
| `auto` example merges once CI green | `skills/quickfix/SKILL.md:53-54`: "The positional `auto` token enables / auto-merge via `/land-pr`" |

## Companion skills (per COMPANIONS.md, R6)

| Doc sentence | Source citation |
|---|---|
| "`/do` — the peer of `/quickfix`. ... `/do` uses an isolated worktree where `/quickfix` works in place on main." | COMPANIONS.md per-skill row `quickfix`: "Peer of `/do`; same lifecycle". Source ref `skills/quickfix/SKILL.md:40`: "- `/do pr` — fresh worktree, agent-dispatched, for larger tasks." |
| "`/draft-plan` and `/run-plan` — where `/quickfix` sends you when a request is too large" | `skills/quickfix/SKILL.md:568-569` (redirect targets, quoted above). COMPANIONS.md: "triage redirects to `/draft-plan`/`/run-plan`". |
| "`/investigate` — use this first when you don't yet know the root cause ... the fix it lands on may then be shipped with `/quickfix` or `/do`." | COMPANIONS.md `investigate` row: "Proves a root cause; its fix then routes to `/quickfix` or `/do` (per CLAUDE.md)." |
| "`/fix-issues` — for working through a backlog of GitHub issues in batches" | `skills/quickfix/SKILL.md:42`: "- `/fix-issues pr` — batches of GitHub-issue-driven fixes in per-issue worktrees." |
| "`/land-pr` — the helper `/quickfix` dispatches ... You don't call it yourself." | COMPANIONS.md `land-pr` row: "**Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly." Source `references/exit-codes-and-rules.md:26`: "dispatched via `/land-pr`". |
| "`/cleanup-merged` — run this after your PR merges to catch your local clone up" | COMPANIONS.md `cleanup-merged` row: "Run AFTER any landing skill merges a PR, to catch the local clone up." |

## Arguments

| Doc row | Source citation |
|---|---|
| `<description>` — required on a clean tree, optional with edits | `skills/quickfix/SKILL.md:29-31` (mode table); `SKILL.md:56`: "Empty DESCRIPTION is allowed" |
| `auto` — auto-merge once CI passes; also skips the in-place confirmation | `skills/quickfix/SKILL.md:53-54`: "positional `auto` token enables / auto-merge via `/land-pr`"; `SKILL.md:740`: "**If `$AUTO_FLAG=1`, skip this WI entirely.**" (skips the dirty-tree confirmation) |
| `from-here` — run from a non-main branch | `skills/quickfix/SKILL.md:59-60`: "**from-here** (optional) — override the \"must run on main/master\" / preflight check" |
| `skip-tests` — skip the pre-commit test run, warn-only, hotfix-only | `skills/quickfix/SKILL.md:62-63`: "**skip-tests** (optional) — skip the WI 1.12 test gate. Warn-only; / use only for emergency hotfixes where the test suite is unrelated." |
| `--force` — proceed past a redirect or a rejected review; dashed to match `/do`, `/work-on-plans`, `/cleanup-merged` | `skills/quickfix/SKILL.md:64`: "**--force** (optional) — bypass a triage REDIRECT verdict (WI 1.5.4) and"; `SKILL.md:66`: "`/work-on-plans`, and `/cleanup-merged` — `--force` is a safety-gate" |
| `--branch <name>` — exact branch name override | `skills/quickfix/SKILL.md:811`: "`--branch` overrides verbatim." |
| `--rounds N` — plan-review cycles, default 1, `0` skips review | `skills/quickfix/SKILL.md:48` argument-hint `[--rounds N]`; `SKILL.md:628`: "If `$ROUNDS -eq 0`: print to stderr" + "skip review entirely" (SKILL.md:630) |
| `--no-claim` — treat `#N` references as mentions; default stops on a foreign-held issue; accepted but not in usage line | `skills/quickfix/SKILL.md:68-69`: "**--no-claim** (optional) — treat every bare `#N` in the description as a / mere mention."; `SKILL.md:70`: "`/quickfix` normally STOPS when the description references an issue"; `SKILL.md:81`: "`argument-hint` frontmatter (kept lean per #961); documented here." (body documents arg the argument-hint omits → body wins, per RUBRIC template item 4) |
| "the feature branch is named `quickfix/<short-summary>`, where the prefix comes from your project's `execution.branch_prefix` setting" | `skills/quickfix/SKILL.md:812`: "`execution.branch_prefix` (default `quickfix/`; empty string allowed)." |

## R5 internals-stripped (removed from prior doc)

- All `WI 1.x` work-item IDs removed (RUBRIC R5 / banned-terms `WI [0-9]`).
- `AUTO_FLAG`, `PIPELINE_ID`, `.landed` marker, `.zskills/...`, `claim.json`
  internals removed.
- Mode-by-mode narration ("in PR mode / in worktree mode") avoided; behavior
  stated once (R4). The one genuine config-conditional carve-out (soft-redirect
  on non-PR landing modes) kept as a single scoped paragraph (R3-c / R4).

## R5 — intentional retained terms (user observably encounters)

- `#N` / `#340` in the `--no-claim` row: the user types these issue references
  and reads them back in the STOP message (`skills/quickfix/SKILL.md:330-332`),
  so they are user-observable, not internals voice. Banned-terms `#`-pattern
  hits on markdown headers are grep-comment-line false positives.
