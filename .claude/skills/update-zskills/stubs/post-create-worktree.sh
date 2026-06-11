#!/bin/bash
# post-create-worktree.sh -- runs after a /create-worktree
# invocation succeeds. Replace this no-op with your own setup
# logic (cp .env.local, npm install, seed restore, etc.).
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
