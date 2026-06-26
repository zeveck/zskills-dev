# Setup Stories

Five setups showing different ways to use zskills. Each one is a complete
path from install to working — pick the one that matches your situation,
or read through them to see what's possible.

> **Already installed?** Skip to the story that fits:
> [Quick evaluation](#1-quick-evaluation) ·
> [Understanding enforcement](#2-understanding-enforcement) ·
> [Solo / direct mode](#3-solo-developer) ·
> [Team adoption](#4-team-adoption) ·
> [Software factory](#5-software-factory)

## Background: attended vs autonomous

Zskills registers hooks in Claude Code that check commands before they
run. Each hook decides whether to block or stay silent based on one
signal: whether a human is present. Claude Code's permission mode
(set at session start — `default` for normal interactive use) tells
the hooks which situation they're in:

| Session type | How it's detected | Demotable checks | Hard checks |
|---|---|---|---|
| **Attended** | `default`, `acceptEdits`, or `plan` mode; no live pipeline | **Silent** (no output) | Block |
| **Autonomous** | `bypassPermissions`, unrecognized mode, or live pipeline marker | **Block** | Block |

Hard checks (`git_destructive`, `fs_destructive`, `process_kill`,
`--no-verify`, `stale_skill_version`, `gh_pr_merge_auto`) always block —
they prevent catastrophic mistakes regardless of who's watching.

This is automatic. A normal interactive session is attended. An unattended
agent is autonomous. Nothing to configure.

---

## 1. Quick Evaluation

> Install once, use skills across projects, don't think about enforcement.

**Setup:**

```bash
# From any terminal (not inside Claude Code):
claude plugin install zs@zskills
```

Open Claude Code in a project:

```
/zs:update-zskills
```

It asks one question — how finished work reaches your repo (pick the
default: feature branch with PR). It auto-detects your test command and
dev server from `package.json`, then writes a project config. About 10
seconds.

No hooks configuration needed. No env vars. No user config file.

**What using skills looks like:**

```
/zs:do Add a health check endpoint
```

The agent creates a worktree on a feature branch, implements the feature,
runs tests, verifies with a fresh reviewer, pushes the branch, and opens a
PR. Review on GitHub and merge.

No warnings appear. No blocks fire. No enforcement output. The hooks run
silently in the background because the session is attended.

**Why it's silent:**

Because a human is present (`default` permission mode), all coaching
checks stay silent — they only activate for unattended agents. The
experience is identical to having no hooks installed.

**Opening another project:**

The plugin is machine-wide. Open any project, run `/zs:update-zskills`
(one question, 10 seconds), start using skills. Each project gets its own
config with auto-detected settings.

---

## 2. Understanding Enforcement

> See what hooks actually do. Poke the guardrails. Verify that attended
> developers won't be nagged. Learn how to tune individual checks.

**Setup:** Same install as Story 1. To simulate an unattended agent,
start Claude Code with `--dangerously-skip-permissions` (this sets
`bypassPermissions` mode, making hooks treat the session as autonomous).

**What autonomous enforcement looks like:**

Ask the agent to `git add .`:

```
BLOCKED: git add . / git add -A sweeps in ALL changes, including other
sessions' work. Stage files by name: git add file1 file2.
[hooks.git_discipline.git_add_all — block|off in .claude/zskills-config.json; currently: autonomous default]
```

Ask the agent to `rm -rf ~/projects`:

```
BLOCKED: recursive rm requires a literal /tmp/<name> path. Variables,
wildcards, or paths outside /tmp/ are unsafe.
[hooks.fs_destructive.rm_recursive — block|off in .claude/zskills-config.json; currently: hard default]
```

Notice the difference: `git_add_all` shows `autonomous default` (demotable
— only blocks when autonomous). `rm_recursive` shows `hard default` (hard
— blocks always, even for attended users).

**Switch back to attended mode** (restart Claude Code normally, without
`--dangerously-skip-permissions`) **and try the same things:**

- `git add .` → **silent** (no output; Claude Code's own permission prompt
  still fires)
- `rm -rf ~/projects` → **blocked** (hard check, blocks always)

**The design boundary:** Hard checks (destructive ops) always block.
Coaching checks are silent when watched, block when autonomous. An
attended developer can push to main, can `git add .` — but can never
`rm -rf` or `kill -9`.

**Tuning a single check:**

In `.claude/zskills-config.json`:
```json
{
  "hooks": {
    "git_discipline": {
      "git_add_all": "off"
    }
  }
}
```

Now even autonomous agents can `git add .` in this project.

**Personal override across all projects** (`~/.claude/zskills-config.json`):

```json
{
  "hooks": {
    "pr_discipline": {
      "gh_pr_create": "off"
    }
  }
}
```

Agents can call `gh pr create` directly everywhere (unless a project locks
that check). To disable all enforcement at once: `export ZSKILLS_ENFORCEMENT=off`.

---

## 3. Solo Developer

> Build alone. Want agent planning and verification but zero branch
> ceremony. No PRs, no worktrees, no feature branches. Just main.

**Setup:**

```
/zs:update-zskills direct
```

This sets `execution.landing: "direct"` and
`execution.main_protected: false`.

**What using skills looks like:**

```
/zs:draft-plan quiz Build an argument parser with subcommands.
/zs:run-plan docs/plans/argument-parser.md
```

The agent implements phase by phase — each phase verified by a fresh
reviewer, tested, committed directly to main. No worktree overhead.
Inspect each commit on main as it lands.

**Which hooks activate in direct mode:**

| Group | Fires? | Why |
|---|---|---|
| `git_destructive` | Yes (hard) | Destroying git state is dangerous on any branch |
| `fs_destructive` | Yes (hard) | `rm -rf` is dangerous regardless of workflow |
| `process_kill` | Yes (hard) | `kill -9` can kill container-critical processes |
| `git_discipline` | Partially | `--no-verify` hard; `git_add_all` demotable (silent when attended) |
| `main_protection` | **No** | Gated on `main_protected: true` — not set |
| `pr_discipline` | **No** | Gated on `landing == "pr"` — not set |
| `tracking` | If pipeline active | Only when a skill writes `.zskills/tracked` |

For attended use: only hard checks could fire, and only on genuinely
dangerous commands. In practice: invisible.

**Result:** Plan → implement → verify → test → commit on main. Safety net
for catastrophic mistakes. Zero friction for normal work.

**Switching later:** To move to a PR workflow:

```
/zs:update-zskills locked-main-pr
```

Changes two fields. Everything else (test commands, dev server, hooks
config) stays the same.

---

## 4. Team Adoption

> Shared repo, multiple developers, parallel agent work. Want safety
> guarantees that individual developers can't relax, but freedom to tune
> coaching checks.

**Setup:** Install with `locked-main-pr` (the default). Then the tech lead
edits `.claude/zskills-config.json`:

```json
{
  "execution": {
    "landing": "pr",
    "main_protected": true,
    "branch_prefix": "feat/"
  },
  "testing": {
    "full_cmd": "pytest tests/ -x --timeout=60",
    "output_file": ".test-results.txt"
  },
  "hooks": {
    "git_destructive": { "no_override": true },
    "fs_destructive": { "no_override": true },
    "process_kill": { "no_override": true },
    "main_protection": {
      "config_hooks_tamper": { "value": "block", "no_override": true }
    }
  }
}
```

**What `no_override` does:**

A developer's personal config (`~/.claude/zskills-config.json`) CANNOT
relax locked checks. They can tighten (add `"block"` where the default is
silent) but cannot set `"off"` where the project says `"block"`. If
someone tries:

```
[hooks.git_destructive.reset_hard — LOCKED by project (no_override); currently: project policy (no_override)]
```

**What locked `config_hooks_tamper` does:**

Editing the hooks section of the project config is blocked — for both
attended and autonomous sessions. This check protects itself: even if an
agent disables the surrounding hook group first, this specific check
still fires because it reads the config as it existed before the edit
attempt. An agent can't disarm enforcement before acting.

**What each developer can tune:**

Coaching checks that aren't locked. Personal config:

```json
{
  "hooks": {
    "git_discipline": {
      "git_add_all": "off"
    }
  }
}
```

Works — `git_add_all` isn't locked. Can't touch `git_destructive` or
`fs_destructive`.

**Parallel work (two pipelines, one repo):**

Developer A runs `/zs:run-plan docs/plans/add-auth.md`. Developer B runs
`/zs:fix-issues 5`. Both autonomous.

Each pipeline gets its own tracking subdir:
- `.zskills/tracking/run-plan.add-auth/`
- `.zskills/tracking/fix-issues.sprint-17/`

Claim gates prevent collisions: if one pipeline holds an issue, the other
is blocked from working it. The agent skips to the next issue.

Tracking enforcement prevents shipping incomplete work: before
`git commit` or `git push`, the hook checks that all `requires.*` markers
have matching `fulfilled.*` in that pipeline's subdir.

**Attended developers:** Zero enforcement on demotable checks. Can commit
to main manually, push, whatever. Only autonomous sessions are gated
(except `config_hooks_tamper`, which blocks config edits for everyone).

**Result:** Safety floor that can't be relaxed. Tamper-proof config.
Personal freedom on coaching. Collision-free parallel pipelines. Zero
friction for interactive work.

---

## 5. Software Factory

> Run agents continuously. Triage from a dashboard, feed plans and
> issues in, watch PRs come out.

**Setup:**

Install with `locked-main-pr` (the default). Start the dashboard:

```
/zs:zskills-dashboard start
```

This launches a local web UI (localhost, auto-assigned port) showing
plans, issues, worktrees, and a drag-and-drop priority queue. Open it
in your browser — it's where you'll triage and order work.

**The daily loop:**

1. **Quality audit** — schedule a daily QE pass that reviews recent
   commits for coverage gaps and files GitHub issues for findings:

   ```
   /zs:qe-audit every day at 9am
   ```

   Each morning, the agent reviews what changed, stress-tests weak spots,
   and files issues. Those issues appear in the dashboard's issue queue.

2. **Draft plans** — when you want a bigger feature, describe it and let
   the adversarial drafter produce a solid plan:

   ```
   /zs:draft-plan Add a batch export endpoint with CSV and JSON formats.
   ```

   The plan lands in `docs/plans/` and appears in the dashboard's plan
   queue.

3. **Triage from the dashboard** — drag issues and plans into the Ready
   column in priority order. This is your steering wheel — the agents
   work whatever's at the top.

4. **Issue worker** — a recurring fix loop that pulls from the dashboard
   queue:

   ```
   /zs:fix-issues 1 every 30m dashboard auto now
   ```

   `now` means run immediately AND start the recurring schedule (rather
   than waiting 30 minutes for the first fire). Every 30 minutes, the
   agent picks the top Ready issue, fixes it in a worktree, verifies,
   and opens a PR. `auto` means no confirmation prompts — it lands the
   PR and moves on. When the queue is empty, it exits cleanly.

5. **Plan worker** — same pattern for plans:

   ```
   /zs:work-on-plans 1 every 1h now
   ```

   Every hour, the agent picks the top Ready plan, executes it phase by
   phase (each phase verified and tested), and opens a PR. Plans with
   multiple phases produce one PR per plan, landing all phases together.

**What you do vs. what agents do:**

| You | Agents |
|-----|--------|
| Write plan descriptions (`/zs:draft-plan ...`) | Produce full plan docs via adversarial review |
| Drag items into Ready (dashboard) | Execute in priority order |
| Review PRs on GitHub, merge | Handle implementation, testing, verification |
| Read the dashboard for status | Report via PRs and tracking markers |

**What the hooks protect:**

All agent work runs autonomously (`bypassPermissions` or cron-fired in
a long-running session). Every demotable check is active:

- Agents can't `git add .` (must stage files by name)
- Agents can't push to main (must go through PR)
- Agents can't `rm -rf` or `kill -9` (hard checks, always blocked)
- Agents can't edit the hooks config (tamper gate)

You review PRs. Agents produce them. The dashboard shows what's queued,
in-flight, and done.

**Scaling up:**

- Increase the issue worker count: `/zs:fix-issues 3 every 30m dashboard auto now`
  (fixes up to 3 per fire)
- Run plan and issue workers in the same session — they use claim gates
  to avoid collisions
- Add `/zs:qe-audit bash every 4h` for adversarial stress-testing
  between commit audits

**Note:** Recurring schedules are session-scoped — they run as long as
the Claude Code session is open. Close the terminal and the workers
stop. Re-run the `/zs:fix-issues ... every ...` and
`/zs:work-on-plans ... every ...` commands in a new session to restart
them.

**Result:** You triage from a dashboard, agents execute continuously,
PRs arrive for review. Quality audits feed the issue queue. Plans feed
the plan queue. The hooks ensure agents can't bypass the PR flow or do
anything destructive.

---

## Hooks vs. Skills vs. Landing Mode

| Concept | Controls | Changed by |
|---|---|---|
| **Landing mode** | Where work happens (main vs worktree) and how it ships (commit vs PR) | `/zs:update-zskills <mode>` or `execution.landing` in config |
| **Skills** | What the agent does (plan, implement, verify, test, land) | Which skill you invoke and its arguments |
| **Hooks** | What the agent is NOT allowed to do (safety net) | `hooks.*` config, kill switch, user override |

**Common confusions:**

- "Turn off hooks" ≠ "simplify workflow." Want less ceremony? Change
  landing mode to `direct`. Want less enforcement? Disable hooks.
- "Hooks are silent" ≠ "hooks are off." In attended mode, demotable hooks
  are silent (they do nothing). They're still loaded and would fire if
  the session became autonomous.
- "`locked-main-pr` works fine with hooks off." The skill still uses a
  worktree and opens a PR — that's skill logic, not hook enforcement.
  The hooks just prevent the agent from *accidentally* bypassing the PR
  flow by pushing to main directly.
