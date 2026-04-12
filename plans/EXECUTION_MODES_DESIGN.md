# Execution Modes — Design Decisions

This document captures design decisions from the April 2026 design session.
It is the spec that the execution modes plan must follow. NOT a plan itself —
no phases, no work items. Just decisions, rationale, and constraints.

## The Three Landing Modes

| Mode | Keyword | Isolation | Landing | Good for |
|------|---------|-----------|---------|----------|
| Cherry-pick | (default) | Worktree (auto-named) | Cherry-pick to main | Current behavior, backward compat |
| PR | `pr` | Persistent worktree (named branch) | Push + `gh pr create` | Team review, CI gates, protected main |
| Direct | `direct` | None (work on main) | Already on main | Solo prototyping |

Keyword is `direct` NOT `main` — `main` collides with plan filenames containing "main".

## PR Mode Design

**Persistent worktree on a named feature branch.**

NOT branch checkout in the main working directory. We confirmed that branch
checkout causes: stash/pop data loss (already happened in project history),
tracking enforcement deadlock, and progress tracking failure across cron turns.
Always use worktrees.

**Branch naming:** `{branch_prefix}{plan-slug}` (e.g., `feat/thermal-domain`).
`branch_prefix` from config (default `feat/`). Deterministic from plan file path.

**Worktree path:** `/tmp/<project>-pr-<plan-slug>`. Deterministic. Persists
across cron turns for chunked execution.

**One branch per plan.** All phases accumulate on the same branch. One PR at
the end covers the whole plan. Agent never waits for merge mid-execution.

**One PR per issue** for `/fix-issues`. Each issue gets its own worktree with
a named branch (`fix/issue-NNN`), its own PR with `Fixes #NNN` linking.

**Verification before commit.** Same as cherry-pick mode — impl agent writes
code, verification agent verifies and commits. The tracking system enforces
this regardless of landing mode.

**PR creation flow (final phase):**
```bash
cd "$WORKTREE_PATH"
git push -u origin "$BRANCH_NAME"
gh pr create --title "..." --body "..." --base main --head "$BRANCH_NAME"
```

Error handling: check for existing remote branch, existing PR, gh auth failure.
Fallback: report branch name and manual instructions.

**`.landed` marker for PR mode:** `status: full`, `method: pr`, `branch:`,
`pr:` fields. Compatible with existing cleanup tooling.

**Mixed execution modes banned in PR plans.** If plan-level mode is `pr`,
individual phases cannot use `### Execution: direct`. Delegate is always OK.

## Direct Mode Design

The existing `### Execution: main` behavior, renamed to `direct`:
- No worktree, agent works directly on main
- Commits go to main immediately
- Phase 6 (landing) is a no-op
- `direct` + `main_protected: true` → rejected with error

## Config File

**Location:** `.zskills/config.json` (hook-protected against agent writes,
reads allowed). In our namespace alongside `.zskills/tracking/`.

**Schema:**
```json
{
  "project_name": "my-app",
  "timezone": "America/New_York",
  "source_layout": "...",

  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },

  "testing": {
    "unit_cmd": "npm run test",
    "full_cmd": "npm run test:all",
    "output_file": ".test-results.txt",
    "file_patterns": ["tests/**/*.test.js"]
  },

  "dev_server": {
    "cmd": "npm start",
    "port_script": "scripts/port.sh",
    "main_repo_path": "/workspaces/my-app"
  },

  "ui": {
    "file_patterns": "src/(components|editor|ui)/.*\\.(tsx?|css|scss)$",
    "auth_bypass": "localStorage.setItem('auth', 'bypass')"
  }
}
```

**Replaces:** All `{{PLACEHOLDER}}` values in CLAUDE_TEMPLATE.md and hook
templates. `/update-zskills` reads the config to fill templates.

**Merge algorithm:** Read config → auto-detect from project files → for each
field, config non-empty wins → auto-detected fills gaps → write merged config
back. User-set values are never overwritten by auto-detection.

**Empty values:** Template section gets commented out with TODO marker.

**Backward compatible:** No config = auto-detect (current behavior). Config
is written as side-effect so subsequent runs use it.

## main_protected Hook Enforcement

When `execution.main_protected: true` in config:
- Block `git commit` on main branch
- Block `git cherry-pick` on main branch
- Block `git push` to main
- Allow all of the above on feature branches

This is ACCESS CONTROL, separate from tracking enforcement (PROCESS CONTROL).
Both can be active simultaneously.

The hook reads `main_protected` from config at runtime (not baked in during
/update-zskills). Changing the config takes effect immediately.

## How Execution Modes Interact with Tracking

The tracking system now works correctly (verified, 91 tests). Execution modes
build on top of it:

- **Cherry-pick mode:** Tracking gates cherry-pick to main (existing).
- **PR mode:** Tracking gates push of feature branch (new push enforcement).
- **Direct mode:** No tracking gate (work is already on main, no landing step).

Pipeline association works the same in all modes:
- Worktree agents: `.zskills-tracked` (orchestrator writes it)
- Orchestrators on main: `echo "ZSKILLS_PIPELINE_ID=..."` (transcript-based)

Verification before commit works the same in all modes:
- Impl agent writes code, does NOT commit
- Verification agent verifies and commits
- Tracking markers gate the commit

## Argument Detection

Same pattern as `auto`, `finish`, `stop`:
- `pr` (case-insensitive, last token) → PR landing mode
- `direct` (case-insensitive, last token) → direct landing mode
- Neither → use config default, or `cherry-pick` if no config

```
/run-plan plans/X.md finish auto pr
/run-plan plans/X.md finish auto direct
/fix-issues 10 pr
/research-and-go Build an RPG. pr
```

Config default overridden by argument. `direct` + `main_protected: true` → error.

## Skills That Need Changes

### Core changes:
1. `/run-plan` — argument detection, PR mode Phase 2 dispatch (persistent worktree), Phase 6 landing (push+PR)
2. `/fix-issues` — argument detection, per-issue named branches, Phase 6 PR landing
3. `/research-and-go` — detect mode in goal, pass to /run-plan cron prompt
4. `/draft-plan` — embed landing hints in generated plans when config specifies non-default

### Smaller changes:
5. `/do` — `pr` option (worktree with named branch, push, PR)
6. `/commit` — `pr` subcommand (push current branch, create PR)
7. `/research-and-plan` — pass mode context to /draft-plan
8. CLAUDE_TEMPLATE.md — document execution modes
9. `/update-zskills` — read config file, audit execution mode rules

### No changes needed:
- `/verify-changes` — already scope-aware
- `/briefing` — read-only
- `/investigate` — read-only

## What the Old Plan Got Wrong (Do NOT Repeat)

1. **Assumed worktree exemption for tracking** — tracking now enforces everywhere
2. **Used branch checkout in main directory** — causes stash data loss, tracking deadlock
3. **Had staleness bypass** — removed, enforcement is unconditional
4. **Used `.zskills-tracked` on main** — now uses transcript ZSKILLS_PIPELINE_ID=
5. **Used glob matching for sentinels** — now uses exact scope
6. **`main` as keyword** — collides with filenames, use `direct`
7. **Impl agent commits** — now verification agent commits after verification
8. **Three-tier pipeline guard** — now two-tier
9. **Used `.claude/tracking`** — now `.zskills/tracking` (permission prompts)

## Open Questions

1. **CI integration:** How to handle CI failures on PRs. Research says agents
   read failure logs and push fixes (Devin, Copilot pattern). Not in scope
   for initial implementation but worth designing for.

2. **Auto-merge:** `gh pr merge --auto --squash` queues merge for when checks
   pass. Config could include `auto_merge: true`. Low priority — user can
   merge manually.

3. **Config location finality:** We discussed both `.claude/zskills-config.json`
   (Claude Code's namespace, permission-protected) and `.zskills/config.json`
   (our namespace, hook-protected). The hook already protects `.zskills/config`.
   Either works; the plan should pick one and be consistent.
