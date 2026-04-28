---
name: create-worktree
disable-model-invocation: false
argument-hint: "<slug> [--prefix P] [--branch-name REF] [--from B] [--root R] [--purpose TEXT] [--pipeline-id ID] [--allow-resume] [--no-preflight]"
description: >-
  Create a git worktree for agent work. Thin wrapper around
  .claude/skills/create-worktree/scripts/create-worktree.sh — owns prefix-derived path, optional
  --branch-name override, optional pre-flight prune+fetch+ff-merge,
  worktree-add-safe.sh call with TOCTOU-race remap, and sanitised
  .zskills-tracked / .worktreepurpose writes. Prints the worktree
  path on stdout; all progress/errors go to stderr.
---

# /create-worktree — Unified Worktree Creation

Thin skill wrapper around `.claude/skills/create-worktree/scripts/create-worktree.sh`. The script is the spec; this file exists for discoverability and to document the invocation contract. Do not duplicate the script's logic here.

## Two-tier contract

This skill has two kinds of callers. Both ultimately run the same script; they differ only in whether `--pipeline-id` is specified upfront.

**Tier 1 — bash callers inside other skills** (e.g. `/run-plan`, `/fix-issues`, `/do`). These know their canonical pipeline ID (`run-plan.<tracking-id>`, `fix-issues.<sprint-id>`, `do.<task-slug>`, etc.) and **must pass it verbatim via `--pipeline-id`**. The script rejects invocations without the flag (rc 5). There is no env-var fallback and no silent default — the flag is required so mis-wired call sites fail loudly instead of producing a wrong `.zskills-tracked`.

**Tier 2 — user / Claude invoking `/create-worktree` as a slash command.** Users say "make a worktree called `foo-task`" and don't know or care what a pipeline ID is. When the user omits `--pipeline-id`, Claude (reading this skill) **synthesises `create-worktree.<slug>`** and passes it to the script. A power user who wants a specific pipeline ID can still pass `--pipeline-id` explicitly; Claude passes it through unchanged.

This is why the script is strict but the skill is ergonomic.

## Invocation

Invoke via `$CLAUDE_PROJECT_DIR` (works from any CWD, including nested worktrees):

```bash
WT_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
  --pipeline-id "<id>" \
  [--prefix P] [--branch-name REF] [--from B] [--root R] \
  [--purpose TEXT] [--allow-resume] [--no-preflight] \
  <slug>)
```

**For tier-1 callers:** `--pipeline-id` is the skill's canonical ID (e.g. `run-plan.${TRACKING_ID}`).

**For tier-2 user invocations without an explicit flag:** Claude synthesises `--pipeline-id "create-worktree.<slug>"` (or `create-worktree.<prefix>.<slug>` when `--prefix` is given) and passes it to the script. This default is owned at the skill layer and never happens inside the script.

## Arguments

- `<slug>` (required, positional) — last non-flag token. Must match `[A-Za-z0-9._-]+`.
- `--pipeline-id ID` (**required**) — the value written (after sanitisation) to `.zskills-tracked`. Tier-1 callers pass their canonical pipeline ID. Tier-2 standalone invocations synthesise `create-worktree[.${PREFIX}].${SLUG}` at the skill layer if the user omitted a flag.
- `--prefix P` — adds `P-` to branch name and path leaf. Slashes rejected (rc 5).
- `--branch-name REF` — overrides branch verbatim; path leaf is unchanged. Slashes in the ref are legal (refs under `refs/heads/`).
- `--from B` — base branch for pre-flight and `worktree-add-safe.sh`. Default `main`.
- `--root R` — override `${WORKTREE_ROOT}/${PROJECT_NAME}` stem. Path becomes `${R}/[${PREFIX}-]${SLUG}`.
- `--purpose TEXT` — write `.worktreepurpose` with this text. Without this flag, the script does NOT write `.worktreepurpose`; caller/agent retains responsibility.
- `--allow-resume` — export `ZSKILLS_ALLOW_BRANCH_RESUME=1` to `worktree-add-safe.sh` (permits attach-to-existing-branch that is ahead of base).
- `--no-preflight` — skip `git worktree prune`, `git fetch origin <BASE>`, `git merge --ff-only origin/<BASE>`. Preserves pre-migration semantics for `/do` worktree mode.

## Path template

`PROJECT_NAME=$(basename "$MAIN_ROOT")`. Final path is `realpath -m`:

| Invocation | Path | Branch |
|---|---|---|
| `... <slug>` | `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}` | `wt-${SLUG}` |
| `... --prefix P <slug>` | `${WORKTREE_ROOT}/${PROJECT_NAME}-${P}-${SLUG}` | `${P}-${SLUG}` |
| `... --root R <slug>` | `${R}/${SLUG}` | `wt-${SLUG}` |
| `... --root R --prefix P <slug>` | `${R}/${P}-${SLUG}` | `${P}-${SLUG}` |

`WORKTREE_ROOT` comes from `execution.worktree_root` in `.claude/zskills-config.json`; default `/tmp`.

## Stdout contract

On success (rc=0), stdout is exactly one line: the absolute worktree path. All progress and error messages go to stderr. Callers may safely `WT_PATH=$(bash … <slug>)` and `cd "$WT_PATH"`.

## Exit codes

| Code | Meaning | Retryable |
|------|---------|-----------|
| 0 | Worktree created (fresh, recreated, or resumed) | — |
| 2 | Path exists (incl. TOCTOU remap) | No (operator decides) |
| 3 | Poisoned branch (behind base, 0 ahead) | No |
| 4 | Branch ahead of base without `--allow-resume` | No |
| 5 | Input validation — missing `--pipeline-id`, bad slug, slash in `--prefix`, unknown flag, not in git, install-integrity | No |
| 6 | Pre-flight fetch failed | Yes |
| 7 | Pre-flight ff-merge not possible (divergent base) | No |
| 8 | Post-create write failed (worktree rolled back) | Maybe |

Codes 2/3/4 propagate from `.claude/skills/create-worktree/scripts/worktree-add-safe.sh`. Code 2 also covers the TOCTOU remap when the path materialises mid-flight.

## Post-create side effects

- `.zskills-tracked` is always written with the sanitised `--pipeline-id` value.
  The script requires the flag — there is no env-var path and no fallback.
  The value is passed through `.claude/skills/create-worktree/scripts/sanitize-pipeline-id.sh` before being written.
- `.worktreepurpose` is written iff `--purpose` was given.
- Both files are untracked and not safe to commit — `.claude/skills/commit/scripts/land-phase.sh`
  refuses to clean up a worktree that has git-tracked copies of either.

## Pointer

Authoritative spec: [`scripts/create-worktree.sh`](scripts/create-worktree.sh). Edit there; this wrapper should stay thin.
