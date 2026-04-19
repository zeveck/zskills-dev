---
name: create-worktree
disable-model-invocation: false
argument-hint: "<slug> [--prefix P] [--branch-name REF] [--from B] [--root R] [--purpose TEXT] [--allow-resume] [--no-preflight]"
description: >-
  Create a git worktree for agent work. Thin wrapper around
  scripts/create-worktree.sh — owns prefix-derived path, optional
  --branch-name override, optional pre-flight prune+fetch+ff-merge,
  worktree-add-safe.sh call with TOCTOU-race remap, and sanitized
  .zskills-tracked / .worktreepurpose writes. Prints the worktree
  path on stdout; all progress/errors go to stderr.
---

# /create-worktree — Unified Worktree Creation

Thin skill wrapper around `scripts/create-worktree.sh`. The script is the spec; this file exists for discoverability and to document the invocation contract. Do not duplicate the script's logic here.

## Invocation

Compute `MAIN_ROOT` before invoking (works from any CWD, including nested worktrees):

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
WT_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
  [--prefix P] [--branch-name REF] [--from B] [--root R] \
  [--purpose TEXT] [--allow-resume] [--no-preflight] \
  <slug>)
```

## Arguments

- `<slug>` (required, positional) — last non-flag token. Must match `[A-Za-z0-9._-]+`.
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
| 5 | Input validation (bad slug, slash in `--prefix`, unknown flag, not in git, install-integrity) | No |
| 6 | Pre-flight fetch failed | Yes |
| 7 | Pre-flight ff-merge not possible (divergent base) | No |
| 8 | Post-create write failed (worktree rolled back) | Maybe |

Codes 2/3/4 propagate from `scripts/worktree-add-safe.sh`. Code 2 also covers the TOCTOU remap when the path materializes mid-flight.

## Post-create side effects

- `.zskills-tracked` is always written with the sanitized pipeline ID.
  `ZSKILLS_PIPELINE_ID` is consulted first; fallback is
  `create-worktree[.${PREFIX}].${SLUG}`. The value is passed through
  `scripts/sanitize-pipeline-id.sh`.
- `.worktreepurpose` is written iff `--purpose` was given.
- Both files are untracked and not safe to commit — `scripts/land-phase.sh`
  refuses to clean up a worktree that has git-tracked copies of either.

## Pointer

Authoritative spec: [`scripts/create-worktree.sh`](../../scripts/create-worktree.sh). Edit there; this wrapper should stay thin.
