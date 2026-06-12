#!/bin/bash
# post-create-worktree.sh -- runs after a /create-worktree
# invocation succeeds. Replace this no-op with your own setup
# logic (cp .env.local, dependency install, seed restore, etc.).
#
# THIS IS THE place for per-project worktree bootstrap. A fresh
# worktree is a clean checkout: it has NO node_modules, NO
# generated dependency dirs, and NO git hooks installed (e.g. a
# husky `.husky/_/` dir is absent until the project's prepare
# step runs). If your project's git hooks aren't installed, every
# `git commit` in the worktree fails. Bootstrap them HERE, once,
# instead of baking install commands into agent dispatch prompts.
#
# Canonical npm shape (customize to YOUR project's commands):
#
#     set -euo pipefail
#     WT_PATH="$1"
#     cd "$WT_PATH"
#     npm i              # install deps INTO the worktree
#     npm run prepare    # install git hooks (husky etc.)
#
# Use whatever your project actually uses: `pnpm install`,
# `yarn install`, `bundle install`, `poetry install`, a Makefile
# target, etc. The point is to make the worktree commit-ready.
#
# DO NOT symlink node_modules from the main repo, e.g.
#     ln -s ../main-repo/node_modules node_modules   # <-- DON'T
# A symlinked node_modules shares build-tool state (vite / webpack
# / esbuild caches, .vite, .cache dirs) between worktrees, which
# causes stale-cache corruption: the worktree builds against the
# main repo's cached modules and serves wrong output. Always do a
# real install into the worktree (it's slower but correct). If
# install time is the concern, prefer your package manager's own
# cache/store (npm/pnpm/yarn keep a shared global cache that is
# safe to share) over symlinking the project-local node_modules.
#
# Arguments (positional):
#   $1  WT_PATH       absolute worktree path
#   $2  BRANCH        feature branch name
#   $3  SLUG          slug portion of branch
#   $4  PREFIX        prefix portion of branch (or empty)
#   $5  PIPELINE_ID   pipeline ID written to .zskills/tracked
#                     (NOTE: this is a CONSUMER stub — installed copies do
#                     not auto-update. Worktrees created before the Phase 8
#                     root-turd consolidation carried the ID at the root
#                     path .zskills-tracked; new worktrees carry it at
#                     .zskills/tracked. If your stub reads the marker file
#                     directly, read the new path and fall back to the old
#                     one during the transition window.)
#   $6  MAIN_ROOT     source repo root (for cp .env.local etc.)
#
# Exit code: non-zero fails create-worktree (the worktree is
# left in place for inspection — clean it up manually if you
# want it gone). Empty stdout = no-op; zskills ignores stdout
# for this callout.
#
# See .claude/skills/update-zskills/references/stub-callouts.md.
exit 0
