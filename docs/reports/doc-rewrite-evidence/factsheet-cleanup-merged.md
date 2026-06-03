# Fact sheet — docs/skills/cleanup-merged.md

Each doc claim is paired with its supporting source line(s). Source of truth:
`skills/cleanup-merged/SKILL.md` (read in full). Line numbers are from that
file at HEAD of the worktree `/tmp/zskills-pr-user-doc-rewrite-plan`.

Companion claims (R6) are drawn from
`docs/reports/doc-rewrite-evidence/COMPANIONS.md`, not from the SKILL body —
cited separately at the end.

---

## "What it does"

**Doc:** "After you merge a pull request on GitHub, your local clone still has
the old branch checked out … `/cleanup-merged` brings the clone back in sync."
- `skills/cleanup-merged/SKILL.md:21-24`: "`/cleanup-merged` catches your local clone up after a PR merges on GitHub. It does three things in order: fetch-and-prune, switch to the main branch and pull, then delete local feature branches whose remotes are gone or whose PRs are merged."

**Doc:** "It runs three steps in order: it fetches from `origin` and prunes
stale remote-tracking refs; if you are currently on a merged feature branch it
switches you to `main` and pulls the latest; then it deletes the local feature
branches whose work has already landed on `main`."
- `skills/cleanup-merged/SKILL.md:22-24`: "It does three things in order: fetch-and-prune, switch to the main branch and pull, then delete local feature branches whose remotes are gone or whose PRs are merged."
- `skills/cleanup-merged/SKILL.md:256-257`: "echo \"Fetching origin with --prune...\"" / "if ! git fetch origin --prune; then"
- `skills/cleanup-merged/SKILL.md:274-279` (Phase 3 heading + body): "Switch off a merged feature branch (if applicable)" … "switch to main so we can delete the branch later."
- `skills/cleanup-merged/SKILL.md:314,324`: "## Phase 4 — Pull main" / "echo \"Pulling $MAIN_BRANCH...\""

**Doc:** "A branch counts as 'already landed' when any of these is true: its
upstream on the remote is gone, its PR shows as merged, or its tip is fully
contained in `main` (zero commits ahead)."
- `skills/cleanup-merged/SKILL.md:333-337`: "For every local branch … check three signals: upstream gone, PR merged, or the tip is fully contained in main (0 commits ahead — `git merge-base --is-ancestor <branch> main`, issue #781)."
- `skills/cleanup-merged/SKILL.md:423-426`: "MERGED=0 / if [ \"$UPSTREAM_GONE\" -eq 1 ] || [ \"$PR_STATE\" = \"MERGED\" ] || [ \"$CONTAINED\" -eq 1 ]; then / MERGED=1"

**Doc:** "Each of those means the branch carries nothing that isn't already on
`main`, so deleting it loses no work."
- `skills/cleanup-merged/SKILL.md:344-345`: "either way the local commits match a ref already on main (the `git branch -d` below is the losslessness backstop)."
- `skills/cleanup-merged/SKILL.md:408-412`: "a branch whose tip is fully contained in main (0 commits ahead …) carries zero unique commits, so deleting it loses nothing"

**Doc:** "It is safe to run at any time."
- `skills/cleanup-merged/SKILL.md:31`: "Safe to run any time."
- `skills/cleanup-merged/SKILL.md:785-786`: "Running it with nothing to do is safe and fast"

**Doc:** "The command refuses to do anything if your working tree is dirty —
commit, stash, or discard your changes first"
- `skills/cleanup-merged/SKILL.md:31-32`: "The skill bails on a dirty working tree"
- `skills/cleanup-merged/SKILL.md:246-250`: "if [ -n \"$(git status --porcelain)\" ]; then / echo \"ERROR: working tree is not clean. Commit, stash, or discard changes first.\" >&2 / … exit 3"

**Doc:** "it never deletes a branch that has commits you haven't pushed (unless
you name that branch explicitly with `--force`)."
- `skills/cleanup-merged/SKILL.md:32-33`: "and never deletes a branch with unpushed commits."
- `skills/cleanup-merged/SKILL.md:452-456`: "if [ -n \"$UNPUSHED\" ]; then / echo \"  SKIP   $branch (has unpushed commits; … re-run with '--force' and the branch name)\""

**Doc:** "Running it when there is nothing to clean up just fetches, confirms
`main` is current, and exits."
- `skills/cleanup-merged/SKILL.md:785-786`: "Running it with nothing to do is safe and fast — it fetches, confirms main is current, finds no merged branches, and exits."

**Doc:** "A bare `/cleanup-merged` shows you exactly what it would delete and
ends with a hint to run `/cleanup-merged apply` to execute. Nothing is deleted
until you add `apply`."
- `skills/cleanup-merged/SKILL.md:28-29`: "**Preview by default.** Bare invocation shows what would be deleted. Run `/cleanup-merged apply` to execute."
- `skills/cleanup-merged/SKILL.md:50-51`: "Preview is default — safe to run, self-documenting. Output shows the plan and ends with \"run `/cleanup-merged apply` to execute.\""

**Doc:** "If a merged branch is still checked out in a separate worktree,
`/cleanup-merged` removes that worktree first (when it is clean) before
deleting the branch. A worktree with uncommitted changes is left alone with a
warning … and the main repo's own checkout is never removed."
- `skills/cleanup-merged/SKILL.md:347-353`: "This phase is worktree-aware: if a merged branch is held by a worktree … A worktree that is clean and is not the main repo itself is removed first (`git worktree remove`); a dirty worktree, or the main repo's own worktree, causes the branch to be skipped with a warning"
- `skills/cleanup-merged/SKILL.md:788-792`: "If a merged branch is still held by a clean worktree, `/cleanup-merged` will remove the worktree before deleting the branch. A dirty worktree is left untouched with a warning … The main repo's own worktree is never removed"

---

## "Typical usage"

**Doc:** "The normal flow is two commands — preview, then apply" with
`/cleanup-merged` then `/cleanup-merged apply`.
- `skills/cleanup-merged/SKILL.md:37-38`: "/cleanup-merged                       — preview local (show what would be deleted)" / "/cleanup-merged apply                 — execute local deletions (skip protected)"

**Doc:** `/cleanup-merged all apply` "clean up local + remote in one pass"
- `skills/cleanup-merged/SKILL.md:44`: "/cleanup-merged all apply             — execute both (skip protected)"
- `skills/cleanup-merged/SKILL.md:61`: "**`all`** — both local + remote."

**Doc:** `/cleanup-merged remote apply` "only the remote, leave local alone"
- `skills/cleanup-merged/SKILL.md:42`: "/cleanup-merged remote apply          — execute remote deletions (skip protected)"
- `skills/cleanup-merged/SKILL.md:59-60`: "**`remote`** — adds `git push origin --delete` for branches whose PRs are confirmed MERGED"

**Doc:** `/cleanup-merged apply feat/a feat/b` "only these two local branches"
- `skills/cleanup-merged/SKILL.md:45`: "/cleanup-merged apply <br> <br>...    — narrow to NAMED local branches, then apply"
- `skills/cleanup-merged/SKILL.md:62-67`: "Branch names … narrow the candidate set: only the named branches are considered"

**Doc:** `/cleanup-merged apply --force feat/wip` "delete a named branch not yet
merged"
- `skills/cleanup-merged/SKILL.md:47`: "/cleanup-merged apply --force <br>... — override merged-check + unpushed guard for NAMED branches"
- `skills/cleanup-merged/SKILL.md:68-70`: "**`--force`** … It lets you delete a named branch that is not yet confirmed merged"

**Doc:** "run it after a PR merges, before you start a new feature … or as a
sweep when `git branch` shows stale branches piling up."
- `skills/cleanup-merged/SKILL.md:776-783`: "After `/quickfix`, `/do pr`, `/commit pr`, or any PR-mode skill, once the PR has merged." / "Before starting a new feature so you're branching off up-to-date main." / "As a cleanup sweep when `git branch` shows stale feature branches piling up."

---

## "Arguments"

**Doc:** "order-independent positional tokens plus one dashed flag."
- `skills/cleanup-merged/SKILL.md:109-115`: "Positional tokens: `apply`, `local`, `remote`, `all`. Dashed safety-gate override: `--force`. Order-independent."

**Doc table — `apply`:** "Execute the deletions. Without it, the command only
previews."
- `skills/cleanup-merged/SKILL.md:52-53`: "**`apply`** — positional token meaning \"I saw the preview, do it.\""
- `skills/cleanup-merged/SKILL.md:28`: "**Preview by default.**"

**Doc table — `local`:** "the default, so a bare `/cleanup-merged` and
`/cleanup-merged local` do the same thing."
- `skills/cleanup-merged/SKILL.md:54-57`: "**`local`** … This is also the default when no scope token … is given, so bare `/cleanup-merged` and `/cleanup-merged local` are equivalent"

**Doc table — `remote`:** "Also delete merged branches on the remote
(`origin`). Requires the `gh` CLI for PR-state checking."
- `skills/cleanup-merged/SKILL.md:59-60`: "**`remote`** — adds `git push origin --delete` for branches whose PRs are confirmed MERGED via `gh pr view`."
- `skills/cleanup-merged/SKILL.md:622-624`: "Requires `gh` — if `gh` is unavailable and `remote`/`all` scope is requested, warn and skip."

**Doc table — `all`:** "Both local and remote."
- `skills/cleanup-merged/SKILL.md:61`: "**`all`** — both local + remote."

**Doc table — `<branch>`:** "Any token that isn't a recognized keyword is
treated as a branch name and **narrows** the run"
- `skills/cleanup-merged/SKILL.md:62-65`: "**Branch names** — any positional token that is not a recognized keyword is treated as an explicit branch NAME. Names **narrow** the candidate set: only the named branches are considered (the full-scan is skipped)."

**Doc table — `--force`:** "Override the merged-check and the unpushed-commits
guard — but only for branches you name explicitly."
- `skills/cleanup-merged/SKILL.md:68-70`: "**`--force`** — overrides ONLY the merged-check and the unpushed-commits guard, and ONLY for branches you EXPLICITLY named."

**Doc:** "When you pass branch names, only those branches are considered (the
full scan is skipped). Naming a branch does not bypass safety: each named
branch is still checked for merge status, for unpushed commits, and against the
protected list. Names without `apply` preview only."
- `skills/cleanup-merged/SKILL.md:65-67`: "Names do **not** bypass safety: every named branch is still subject to the merged-confirmation, the unpushed-commits guard, and the protected-skip. Names without `apply` → preview only."

**Doc:** "`--force` … has no effect on branches you didn't name (the full-scan
path ignores it)."
- `skills/cleanup-merged/SKILL.md:70-72`: "`--force` has no effect on un-named branches (the full-scan path ignores it)"
- `skills/cleanup-merged/SKILL.md:175-178`: "if [ \"$FORCE\" -eq 1 ] && [ \"$HAVE_NAMES\" -eq 0 ]; then / echo \"NOTE: '--force' has no effect without explicit branch names … Ignoring.\""

**Doc:** "List branches you want kept under `cleanup.protected_branches` in
`.claude/zskills-config.json`" + the JSON example.
- `skills/cleanup-merged/SKILL.md:75-78`: "**Protected branches** — config field in `.claude/zskills-config.json`:" / "{ \"cleanup\": { \"protected_branches\": [\"docs/run-order-guide\"] } }"

**Doc:** "A protected branch is marked `PROTECTED (config)` in the preview and
skipped during apply. This is sacrosanct — naming a protected branch, even with
`--force`, just prints a refusal notice and skips it. No token or combination
of flags can delete a config-protected branch."
- `skills/cleanup-merged/SKILL.md:79-84`: "Preview marks these as `PROTECTED (config)` and `apply` skips them automatically. **This is sacrosanct: a protected branch is NEVER deleted, even when named explicitly WITH `--force`.** … emits a loud `PROTECTED (config) — refusing to delete even with --force` notice and skips it. There is no flag, token, or naming combination that can delete a config-protected branch."

**Doc:** "The older `--dry-run` / `-n` and `--review` flags still work as aliases
(for one release cycle, removed after 2026-07-01) and print a deprecation
notice"
- `skills/cleanup-merged/SKILL.md:87-90`: "For one release cycle, `--dry-run` / `-n` map to preview (the new default) and `--review` maps to `all` (preview both). Both emit a deprecation notice. Remove after 2026-07-01."

---

## "Companion skills" — drawn from COMPANIONS.md (R6), not the SKILL body

**Doc:** companions are `/commit`, `/do`, `/quickfix`, `/fix-issues`,
`/work-on-plans`, `/land-pr`; relationship = run AFTER any landing skill merges
a PR.
- `COMPANIONS.md:76`: "| `cleanup-merged` | `commit`, `do`, `fix-issues`, `quickfix`, `work-on-plans`, `land-pr` | Run AFTER any landing skill merges a PR, to catch the local clone up. |"
- `COMPANIONS.md:108-109` (peer family): "Execution peers: `do` ↔ `quickfix` (anchor pair), with `commit`, `land-pr`, `cleanup-merged`."

**Doc:** "`/land-pr` … is dispatched for you, not typed directly."
- `COMPANIONS.md:86`: "| `land-pr` | … | **Internal** (`user-invocable: false`). Dispatched BY its callers; never typed directly. |"

**Doc:** "`/commit land` handles the post-landing tidy-up for cherry-pick-mode
worktrees, while `/cleanup-merged` handles the post-merge normalization for
PR-mode work, since a PR merge happens asynchronously when a human clicks
'merge' on GitHub."
- `skills/cleanup-merged/SKILL.md:766-771`: "`/commit land` — post-landing cleanup for cherry-pick mode worktrees." / "`/cleanup-merged` — post-PR-merge cleanup for PR mode (this skill)." / "Cherry-pick commits land on main inline; PR merges are async (human clicks \"merge\" on GitHub), so PR mode needs a separate normalize step."

---

## "Exit codes" table

- `skills/cleanup-merged/SKILL.md:753-762`: the exit-code table — rc 0 "Success (or preview complete)", 1 "Missing required tool (git)", 2 "Bad argument", 3 "Dirty working tree — refuses to proceed", 4 "`git fetch` failed", 5 "`git checkout` or `git pull` failed". (Doc reproduces verbatim.)

---

## Rubric notes

- **R5 (no internals voice):** dropped the `issue #810` reference that the
  prior doc carried on the `--force` row (bare issue number — banned per R5's
  "internal `#issue` links"). The `#781`/`#516`/`#755`/`#816` issue refs in the
  SKILL body are likewise omitted from user prose.
- **R6:** companion section added (the prior doc had none); relationships taken
  verbatim-in-relationship from COMPANIONS.md.
- **R4:** behavior stated once; no mode-by-mode narration. Preview-vs-apply is
  described as one axis (the `apply` token), not narrated per mode.
- **R3-c (true carve-out kept as one clause):** the protected-branch skip and
  the worktree-aware removal are kept as single scoped clauses, not deleted.
- **Banned-term grep:** `grep -nEf docs/reports/doc-rewrite-evidence/banned-terms.txt docs/skills/cleanup-merged.md` returns only markdown-header `#` false-positives (the `#`-comment LINES in banned-terms.txt match any `#`); the comment-stripped grep returns zero hits.
