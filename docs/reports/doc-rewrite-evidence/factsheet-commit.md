# Fact sheet — `docs/skills/commit.md`

Source of truth: `skills/commit/SKILL.md` + `skills/commit/modes/pr.md` +
`skills/commit/modes/land.md` at HEAD. Each row pairs a sentence in the
rewritten doc with the verbatim source line(s) that support it. Line numbers
are from the files as read during this rewrite.

Companion relationships (the "Companion skills" section) are drawn from
`docs/reports/doc-rewrite-evidence/COMPANIONS.md` per R6, cited at the end.

---

## What it does

| Doc sentence | Source citation |
|---|---|
| "`/commit` is the user-facing way to turn the changes in your working tree into a clean commit." / "commit your current work safely" | `skills/commit/SKILL.md:17`: "Commit current work without picking up or harming unrelated changes." |
| "decides which files belong to the work you are committing and which are unrelated, and stages only the related ones" | `skills/commit/SKILL.md:177`: "For every changed and untracked file from `git status -s`, decide:" / `skills/commit/SKILL.md:179`: "1. **Related to current work** — include in this commit" / `skills/commit/SKILL.md:180`: "2. **Unrelated (other agents/sessions)** — leave alone, do NOT touch" |
| "always by name, never with a catch-all `git add`" | `skills/commit/SKILL.md:251`: "**NEVER use `git add .` or `git add -A`** — these grab everything." |
| "if a file you are committing depends on another uncommitted file, that file is pulled in too" | `skills/commit/SKILL.md:221`: "1. Check its imports. If it imports an uncommitted file, that file MUST be included. Recurse." |
| "Unrelated changes are left untouched." | `skills/commit/SKILL.md:450`: "**NEVER touch unrelated changes** — other agents may have work in progress." |
| "If a single file mixes your work with someone else's, the skill stops and asks rather than guessing." | `skills/commit/SKILL.md:213`: "**If a file has mixed changes** (yours + someone else's): STOP. Tell the user which file and what the mixed changes are. Ask what to do." |
| "it runs the full test suite when code was staged (it skips tests for content-only changes like Markdown or images)" | `skills/commit/SKILL.md:272`: "**Run tests if code was staged** — if any staged files are code (`.js`, `.css`, `.html`, `.rs`), run the full test suite before committing" / `skills/commit/SKILL.md:295`: "Skip this step for content-only commits (`.md`, `.jpg`, `.png`, logs)." |
| "drafts a commit message in the style of your recent history" | `skills/commit/SKILL.md:268`: "Follow the style of recent commits (`git log --oneline -10`)" |
| "has a fresh reviewer look over the staged diff to catch missing files, stray files, or problems in the change" | `skills/commit/SKILL.md:312`: "**Dispatch a fresh agent to review the staged changes before committing.**" / `skills/commit/SKILL.md:315`: "Are all related files included? Any missing dependencies?" / `skills/commit/SKILL.md:316`: "Are any unrelated files accidentally staged?" |
| "If anything looks wrong, it stops and reports instead of committing." | `skills/commit/SKILL.md:357`: "If the agent raises concerns: **STOP.** Report the concerns to the user. Do not commit until concerns are resolved." |
| "**Push** the commit to the remote." | `skills/commit/SKILL.md:419`: "## Phase 6 — Push (if `push` argument)" / `skills/commit/SKILL.md:424`: "git push" |
| "**Open a pull request** to main (`/commit pr`) — push the current branch, create the PR, watch its CI, and fix failures, by handing off to the `/land-pr` skill" | `skills/commit/modes/pr.md:7`: "It pushes the current branch and creates a PR to main via the shared `/land-pr` skill (rebase + push + create + CI poll + fix-cycle loop)." |
| "**Land** worktree commits onto main by cherry-picking them (`/commit land`), running tests, and recording that the worktree's work has been merged." | `skills/commit/modes/land.md:7`: "This is for landing worktree work onto main via cherry-pick." / `skills/commit/modes/land.md:39`: "**Run tests after cherry-picks land:**" / `skills/commit/modes/land.md:60`: "**Write `.landed` marker** on the worktree" |
| "If you do not type a mode, `/commit` reads your project's configured default landing behavior and acts accordingly — so on a project set up to land work through pull requests, a bare `/commit` opens a PR for you" | `skills/commit/SKILL.md:31`: "When no explicit mode token is supplied, the skill consults" / `skills/commit/SKILL.md:32`: "`execution.landing` in `.claude/zskills-config.json` to pick the default" / `skills/commit/SKILL.md:139`: "- `/commit` with `execution.landing: \"pr\"` in config → PR mode (config default)" |

## Typical usage

| Doc sentence | Source citation |
|---|---|
| "`/commit` — commit the related changes; figure out the scope from the diffs." | `skills/commit/SKILL.md:20`: "- `/commit` — commit only, infer scope from diffs" |
| "`/commit skill updates` — … the free-text **scope hint** (`skill updates`) guides which files count as related." | `skills/commit/SKILL.md:21`: "- `/commit skill updates` — commit, scope guided by \"skill updates\"" |
| "The hint narrows the search; the skill still checks the diffs." | `skills/commit/SKILL.md:464`: "**Scope hint is advisory, not absolute** — even with a scope hint, check diffs." / `skills/commit/SKILL.md:467`: "The hint narrows the search; it doesn't replace judgment." |
| "`/commit push` — commit, then push to the remote." | `skills/commit/SKILL.md:22`: "- `/commit push` — commit and push to remote" |
| "`/commit pr` — push the current branch and open a pull request to main." / "it requires a clean working tree, so commit first" | `skills/commit/SKILL.md:25`: "- `/commit pr` — push current branch and create a PR to main (requires clean working tree)" |
| "`/commit pr auto` — the same, plus request that the PR auto-merge once CI passes." | `skills/commit/SKILL.md:154`: "- `/commit pr auto` → PR mode + auto-merge (passes `--auto` to `/land-pr`)" / `skills/commit/modes/pr.md:328`: "Without `auto`, `LAND_ARGS` omits `--auto` and the PR settles at" / `skills/commit/modes/pr.md:329`: "`/land-pr` invokes `gh pr merge --auto --squash`." |
| "`/commit pr` is the path to reach for. It is one of the supported entry points for opening pull requests; you do not call the underlying landing machinery yourself." | COMPANIONS.md:77: "`commit pr` dispatches `/land-pr`; peers call it to land." / COMPANIONS.md:86 (land-pr is "**Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly.") |

## Companion skills (R6 — from COMPANIONS.md)

| Doc sentence | Source citation |
|---|---|
| "`/land-pr` — the skill `/commit pr` hands off to … `/land-pr` is an internal helper you do not type directly; reach for it through `/commit pr`." | COMPANIONS.md:77: "The staged-work landing skill; `commit pr` dispatches `/land-pr`; peers call it to land." / COMPANIONS.md:86: "`land-pr` … **Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly." Behavior of the handoff: `skills/commit/modes/pr.md:7`: "via the shared `/land-pr` skill (rebase + push + create + CI poll + fix-cycle loop)." |
| "`/do` and `/quickfix` — peer skills for one-commit changes … and call `/commit` to land their work. … when the project protects its main branch, use `/do` (which works in an isolated worktree); otherwise either works." | COMPANIONS.md:48-52: "**`/quickfix` vs `/do` are PEERS, not tiers.** Same lifecycle; same `/land-pr` dispatch; same one-commit-PR shape. The difference is *where the work tree lives* — `/quickfix` does `git checkout -b` on main; `/do` uses a worktree. Pick by **project policy**: `main_protected: true` → `/do`; otherwise either." / COMPANIONS.md:77: "peers call it to land." |
| "`/run-plan` and `/fix-issues` — larger orchestration skills that also land their work through `/commit` and `/land-pr`." | COMPANIONS.md:77 (commit companions include `run-plan`, `fix-issues`): "The staged-work landing skill; … peers call it to land." / COMPANIONS.md:94: "run-plan … lands phases via `/land-pr`" / COMPANIONS.md:83: "fix-issues … `land-pr`". |
| "`/cleanup-merged` — run this *after* a PR you opened with `/commit pr` has merged, to bring your local clone back up to date." | COMPANIONS.md:76: "cleanup-merged … Run AFTER any landing skill merges a PR, to catch the local clone up." |
| "`/update-zskills` — configures the project settings `/commit` reads, such as the default landing behavior and the commit co-author trailer." | COMPANIONS.md:96: "update-zskills … The install/config skill; configures and is referenced by nearly every skill." Settings read by /commit: `skills/commit/SKILL.md:32` (`execution.landing` from `.claude/zskills-config.json`); `skills/commit/SKILL.md:364`: "The trailer value lives in `.claude/zskills-config.json` under `commit.co_author`." |

## Arguments (template part 4 — cited inline in the doc table)

| Doc sentence | Source citation |
|---|---|
| "`pr` … Must be the **first** token — this prevents a scope hint that happens to contain \"pr\" from triggering PR mode." | `skills/commit/SKILL.md:28`: "**Parsing:** `pr` is recognized ONLY when it is the **FIRST token** in `$ARGUMENTS`." / `skills/commit/SKILL.md:471`: "**`/commit pr` keyword is first-token-only** — prevents false-triggering on scope hints that contain \"pr\" mid-string." |
| "`pr` … Requires a clean working tree." | `skills/commit/SKILL.md:25`: "(requires clean working tree)" / `skills/commit/SKILL.md:468`: "**`/commit pr` requires a clean working tree** — all changes must be committed before running PR mode." |
| "`scope` … Advisory — the skill still reads the diffs." | `skills/commit/SKILL.md:20` (scope-from-diffs example) / `skills/commit/SKILL.md:464`: "**Scope hint is advisory, not absolute** — even with a scope hint, check diffs." |
| "`push` … Commit, then push to the remote." | `skills/commit/SKILL.md:22`: "- `/commit push` — commit and push to remote" / `skills/commit/SKILL.md:419`: "## Phase 6 — Push (if `push` argument)" |
| "`land` … Cherry-pick the current worktree's commits onto main, run tests, and record that the work has landed. Only valid when you are in a worktree." | `skills/commit/SKILL.md:24`: "- `/commit land` — cherry-pick worktree commits into main (worktree only)" / `skills/commit/modes/land.md:10`: "Confirm we're in a worktree (not main). If on main, stop and explain." |
| "`auto` … In PR mode, request that the pull request auto-merge once CI passes. Has no effect with `push` or `land`." | `skills/commit/SKILL.md:154`: "- `/commit pr auto` → PR mode + auto-merge (passes `--auto` to `/land-pr`)" / `skills/commit/SKILL.md:41`: "Setting AUTO_FLAG outside PR mode is a no-op — `push` and `land` modes do not consult it." |
| "If you give no mode token at all, `/commit` reads your project's configured default landing behavior … a bare `/commit` behaves like `/commit pr`." | `skills/commit/SKILL.md:31`: "When no explicit mode token is supplied, the skill consults" / `skills/commit/SKILL.md:139`: "- `/commit` with `execution.landing: \"pr\"` in config → PR mode (config default)" |

---

## R5 internals-stripped (named so the verifier sees they were intentionally dropped)

The following internals from the source are deliberately **absent** from the
user doc (R5): phase numbers (Phase 1–7), script names
(`zskills-resolve-config.sh`, `write-landed.sh`, `pr-push-and-create.sh`,
`sanitize-pipeline-id.sh`), env vars (`AUTO_FLAG`, `SCOPE_HINT`,
`FIRST_TOKEN`, `CLAUDE_PLUGIN_ROOT`, `FULL_TEST_CMD`), marker filenames
(`.landed`, `requires.land-pr.<id>`, `fulfilled.commit.<id>`), the
config-key spellings beyond what a user would set (`commit.co_author`),
result-status tokens (`pr-ready`, `behind-thrash`), and design-decision /
issue refs (`#236`, `#624`, etc.).

## R4 carve-out kept (the one true mode-changing fact)

`land` is genuinely worktree-only and `pr` genuinely requires a clean tree —
these are kept as single scoped clauses in the arguments table, not narrated
mode-by-mode. The config-driven default ("a bare `/commit` may open a PR") is
stated once.
