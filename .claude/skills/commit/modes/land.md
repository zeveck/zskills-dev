# /commit land — Land Worktree Commits

Loaded by /commit when the `land` argument is present; cherry-picks worktree commits into main and records a landing marker.
## Phase 7 — Land (if `land` argument)

Only if `land` was in the arguments.
This is for landing worktree work onto main via cherry-pick.

**Pre-checks:**
- Confirm we're in a worktree (not main). If on main, stop and explain.
- Ensure all worktree changes are committed first (run Phases 1-5 if needed).

**Steps:**

1. **Identify commits to land:**
   ```bash
   git log --oneline main..HEAD
   ```
   Present the list to the user for approval.

2. **Switch to main repo and inventory:**
   ```bash
   cd <main-repo-path>
   git status -s
   ```
   Do NOT stash — it can silently merge or lose other sessions' work. Let
   git's overlap detection handle it in step 3.

3. **Cherry-pick approved commits (try-without-stash):**
   ```bash
   git cherry-pick <commit-hash>
   ```
   One at a time. On any refusal or conflict: **STOP** and report to the
   user. Do not force-resolve, stash, or `--abort` without asking — the
   conflict state preserves evidence.

4. (No stash restore — we never stashed.)

5. **Run tests after cherry-picks land:**
   ```bash
   npm run test:all
   ```
   If tests fail, report to the user. Do NOT attempt to fix — the
   cherry-picked code was already tested in the worktree. A failure here
   means a main-specific conflict that needs human judgment.

6. **Write `.landed` marker** on the worktree (so `/fix-report` knows
   it's safe to remove):
   ```bash
   cat <<LANDED | bash "$CLAUDE_PROJECT_DIR/.claude/skills/commit/scripts/write-landed.sh" "<worktree-path>"
   status: full
   date: $(TZ=America/New_York date -Iseconds)
   source: commit-land
   commits: <list of cherry-picked hashes>
   LANDED
   ```

7. **Verify:**
   ```bash
   git status -s
   git log --oneline -5
   ```

