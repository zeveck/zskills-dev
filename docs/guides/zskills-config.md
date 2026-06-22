# Configuring zskills

Every zskills install is steered by one file: `.claude/zskills-config.json`.
It tells the skills, hooks, and helper scripts how *your* project works — how
to run tests, how changes reach `main`, what the dev server command is, which
timezone to stamp reports in, and more. This guide explains where the file
comes from, what every field does, and which fields you should never hand-edit.

You rarely write this file by hand. `/update-zskills` creates and maintains it
for you (on the plugin lane, the one-time `/zs:update-zskills` init *offers*
one — the file is optional, and without it zskills runs on built-in defaults).
Reach for this guide when you want to understand a setting, change one
deliberately, or debug why a skill behaved the way it did.

## Where it lives

| File | Role |
|---|---|
| `.claude/zskills-config.json` | Your project's settings (this guide). |
| `.claude/zskills-config.schema.json` | The JSON Schema the config validates against — the authoritative list of every key and default. Editors that honor `$schema` will autocomplete and lint against it. |
| `~/.claude/zskills-config.json` | Optional **user tier** — personal defaults that apply across all your projects (see [The config cascade](#the-config-cascade)). |

The config's first line points an editor at that schema:

```json
{
  "$schema": "./zskills-config.schema.json",
  ...
}
```

The schema is the source of truth for field names and defaults; this guide is
the explanation of what they *mean*. The canonical copy lives at
[`config/zskills-config.schema.json`](../../config/zskills-config.schema.json)
in the source repo.

## How it's created and updated

`/update-zskills` owns this file:

- **First install** — `/update-zskills install` auto-detects what it can (test
  command, dev-server command, timezone) and writes the rest as empty strings
  for you to fill in. Running the command *is* the consent; it writes the file
  directly.
- **Re-install / update** — it **merges, never overwrites**: an existing
  non-empty value always wins over a re-detected one, so your edits survive an
  update. A missing `commit.co_author` is backfilled.
- **Plugin lane** — the config is **optional and offered, never imposed**.
  The one-time `/zs:update-zskills` init asks whether you want one; decline
  and zskills runs on its built-in defaults with no file at all. Accept and
  it seeds the defaults (plus the schema sibling) for you to tune. An
  existing config is never clobbered, and init never deletes one. (The
  plugin seed defaults differ slightly; see
  [Lane differences](#lane-differences) below.)

A handful of fields are managed entirely by `/update-zskills` and should not be
hand-edited — see [What not to hand-edit](#what-not-to-hand-edit).

## The config cascade

Settings resolve through three tiers — **project > user > built-ins**:

1. **Project** — `.claude/zskills-config.json` in the repo. Always wins.
   This file (and its schema sibling) is meant to be **committed** — it's the
   project's shared settings, and tracking it is how the whole team gets the
   same test commands, landing mode, and timezone.
2. **User** — `~/.claude/zskills-config.json`. Personal defaults that apply
   in any project that doesn't set its own value (e.g. your timezone, your
   co-author trailer). Create it by hand; nothing writes it for you. It lives
   outside the repo, so it's personal by construction — never committed.
3. **Built-ins** — shipped defaults (timezone `UTC`, landing `direct`,
   output file `.test-results.txt`, port `8080`, …). This is why a
   zero-config project still works.

**The merge rule: top-level blocks merge whole.** If a top-level block (say
`testing`) appears in both your user file and the project file, the
project's block wins **as a unit** — don't split one block's keys across the
two tiers and expect them to knit together. (Nuance: a few bash-side readers
happen to merge the handful of string keys they read per *key* rather than
per block, so a split can appear to work in some places and not others —
treat per-key mixing as undefined and keep blocks whole.)

**What cascades from the user tier — and what does not.** Most of the
`execution` block still describes the *project's* repo discipline and stays
project-only. But the user tier has limited, scoped powers over exactly
**five** keys:

- **Three workflow keys cascade plainly** (project > user > built-ins):
  `execution.landing`, `execution.branch_prefix`, and
  `execution.max_concurrent_worktrees`. If the project sets one, the
  project value wins; if the project leaves it unset, the user-tier value
  applies; otherwise the built-in default does. (Example: a user-tier
  `execution.landing: "pr"` is effective in any project that has no
  `landing` of its own — your personal preference becomes the default
  everywhere you haven't overridden it.)

- **Two safety keys are RAISE-ONLY floors** — the user tier can only make
  protection *stricter*, never looser: `execution.main_protected` (`true`
  wins over `false` — a user `true` protects a project that set `false`,
  but a user `false` can never unlock a project's `true`) and
  `agents.min_model` (the stricter model tier wins; a tie resolves to the
  project value). A user-level file that tried to *lower* a project's
  protection silently does nothing — the floor holds. (Example: user
  `main_protected: true` + project `false` → protected; user
  `main_protected: false` + project `true` → still protected. User
  `min_model: "opus"` + project `"sonnet"` → opus; user `"haiku"` +
  project `"sonnet"` → sonnet, never lowered.)

Everything else in `execution` (e.g. `worktree_root`, the `dashboard_*`
keys) and `zskills_version` stay **project-only** — they are never read
from the user tier. The raise-only floor design preserves the trust
direction: a personal file can tighten a project's safety posture but can
never weaken it, so sharing a machine never silently disarms a repo's
protection. (A malformed user-tier file is ignored entirely — it never
disarms a floor and never errors a hook or the resolver.)

A user-tier file looks just like a project one (minus the `$schema` line,
unless you point it at a local schema copy):

```json
{
  "timezone": "America/New_York",
  "commit": { "co_author": "My Agent <agent@example.com>" }
}
```

## A typical config

This is roughly what `/update-zskills` writes for a Node project. Every block
is optional; an absent key falls back to its default.

```json
{
  "$schema": "./zskills-config.schema.json",
  "project_name": "my-app",
  "timezone": "America/New_York",
  "execution": {
    "landing": "pr",
    "main_protected": true,
    "branch_prefix": "feat/"
  },
  "commit": {
    "co_author": "My Agent <agent@example.com>"
  },
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all",
    "output_file": ".test-results.txt",
    "file_patterns": ["tests/**/*.test.js"]
  },
  "dev_server": {
    "cmd": "npm start",
    "default_port": 8080,
    "main_repo_path": "/home/you/projects/my-app"
  },
  "ui": {
    "file_patterns": "src/(components|ui)/.*\\.tsx?$",
    "auth_bypass": "localStorage.setItem('token', 'test')"
  },
  "logging": {
    "enabled": true,
    "dir": "/home/you/projects/my-app/.zskills/session-logs"
  },
  "agents": {
    "min_model": "auto"
  }
}
```

## Field reference

### `execution` — how work is built and landed

The most load-bearing block. `landing` and `main_protected` together decide
whether the project is PR-only or lets agents work on `main` directly.

| Field | What it does | Default |
|---|---|---|
| `execution.landing` | Default landing mode when a skill isn't given a positional mode token. One of `cherry-pick`, `pr`, `direct`. | `cherry-pick` |
| `execution.main_protected` | When `true`, **autonomous/unwatched** sessions are blocked from editing, committing, cherry-picking, or pushing to `main` — forcing agents through the worktree/PR flow. **Attended/watched humans are unrestricted and silent, regardless of this value** (git plus Claude Code's permission prompt cover attended safety; `main_protected`'s real job is gating agents). A project that wants hard-deny-even-attended sets the relevant `hooks.main_protection.*` toggle to `"block"`. **Enforced** by hooks, not just convention. | `false` |
| `execution.branch_prefix` | Prefix for PR-mode branch names (e.g. `feat/`, `agent/`, or `""`). | `feat/` |
| `execution.worktree_root` | Parent directory for new worktrees (`<root>/<project>-<slug>`). Keeps ephemeral agent work off the repo tree. | `/tmp` |
| `execution.max_concurrent_worktrees` | Cap on live worktrees during a `/fix-issues` sprint — prevents resource exhaustion in constrained containers. | `3` |
| `execution.dashboard_completed_days` | How many days of closed work the dashboard's "Completed" column shows. | `14` |
| `execution.dashboard_completed_limit` | Max closed issues fetched per dashboard snapshot. | `500` |

`landing` and `main_protected` are usually set together by a **preset** rather
than edited by hand — see [Landing & protection](#landing-protection).

### `testing` — how tests run

| Field | What it does | Default |
|---|---|---|
| `testing.unit_cmd` | The fast unit-test command (used while working). | — |
| `testing.full_cmd` | The full-suite command (run before committing). Skills reference this instead of hardcoding a command, so the rule that says "run the suite before every commit" shows *your* command. | — |
| `testing.output_file` | Filename skills capture test output to (kept out of the working tree). | `.test-results.txt` |
| `testing.file_patterns` | Globs identifying test files, surfaced in your project rules. | — |

### `dev_server` — running the app

| Field | What it does | Default |
|---|---|---|
| `dev_server.cmd` | Command that starts your dev server. `scripts/start-dev.sh` runs it; `scripts/stop-dev.sh` stops the recorded PIDs. | — |
| `dev_server.default_port` | The dev port for the **main** repo. Worktrees each get their own deterministic hash-derived port instead. | `8080` |
| `dev_server.main_repo_path` | Absolute path to the main checkout, so worktree agents can tell main-vs-worktree apart when choosing a port. | — |

If you set `main_repo_path` you must also set `default_port`, or the port
helper fails loudly on the main repo.

### `ui` — UI verification

| Field | What it does | Default |
|---|---|---|
| `ui.file_patterns` | Regex matching UI files; changes to them flag that a manual browser pass is warranted. | — |
| `ui.auth_bypass` | JavaScript run to bypass your app's auth during automated browser testing (`/manual-testing`). | — |

### `logging` — session logs

Consumed (and toggled) by the session-logging hooks.

| Field | What it does | Default |
|---|---|---|
| `logging.enabled` | Master switch — **off by default**; set `true` to opt in. When `false` or absent, the session-logging hooks no-op. | `false` |
| `logging.dir` | The **base** directory for session logs — give an **absolute** path. Empty = a per-OS cache base (e.g. `~/.cache/zskills-session-logs` on Linux, `~/Library/Caches/zskills-session-logs` on macOS, `%LOCALAPPDATA%\zskills-session-logs` on Windows). The resolved base is then composed with the optional `<repo>`/`<user>` segments below. The final path is recorded in the main checkout's `.zskills/session-log-dirs` registry (newest last) so you can always find where it logged. | `""` |
| `logging.include_repo` | When `true` (default), append a sanitized `<repo>` segment (the project-dir basename) to the base, so each repo's logs land in their own subdirectory: `<base>/<repo>/...`. Set `false` to write flat to `<base>/...`. | `true` |
| `logging.include_user` | When `true`, append a sanitized `<user>` segment after `<repo>`: `<base>/[<repo>]/<user>/...`. The user identity is resolved at **runtime** (never stored in the committed config): `ZSKILLS_LOG_USER` env > `git config user.email` > OS login > `unknown`. Useful on a shared mount written by multiple developers. | `false` |
| `logging.file_mode` | POSIX octal mode for created log files + permission sidecars. Default `0600` is owner-only — logs can contain credentials a user `cat`-ed, so relaxing this is an explicit opt-in. The **directory mode is derived** by adding a search/exec bit to every read/write triad (`0660→0770`, `0640→0750`, `0600→0700`). **POSIX-only**: on Windows it is a no-op (NTFS/SMB use ACLs). The local registry always stays `0600`. | `"0600"` |

With logging turned on (`logging.enabled: true`), pointing `logging.dir` at a
persistent path gives you a readable per-session transcript and permission trail
— a handy monitoring/audit record, especially for unattended runs (see
[Inspecting & monitoring](inspecting-and-monitoring.md)).

The composed log path is `<base>/[<repo>]/[<user>]/<YYYY-MM-DD-HHMM-session8>.md`.
With the defaults (`include_repo: true`, `include_user: false`, default cache
base) this is byte-identical to a single per-project cache directory.

#### Shared-mount recipe

To point `logging.dir` at a shared mount (NFS/SMB) written by multiple
developers across multiple repos, compose `<repo>/<user>` and relax the mode so
an authorized group can read/write:

```jsonc
"logging": {
  "enabled": true,
  "dir": "/nfs/team/zskills-logs",
  "include_repo": true,
  "include_user": true,
  "file_mode": "0660"
}
```

This yields `/nfs/team/zskills-logs/<repo>/<user>/<session>.md`.

- **POSIX (Linux/macOS share).** zskills sets the file/dir **mode bits** but
  never `chown`/`chgrp`. The admin owns group ownership + inheritance — run once
  on the share root:

  ```bash
  chgrp -R <group> /nfs/team/zskills-logs && chmod -R g+rws /nfs/team/zskills-logs
  ```

  The setgid `s` makes new files/dirs inherit the group. **Caveat:** relaxing
  `file_mode` from `0600` exposes logs (which may contain credentials a user
  `cat`-ed) to the whole group — opt in deliberately.

- **Windows / SMB share.** `file_mode` is a **no-op** on Windows (there are no
  rwx owner/group/other bits; `os.umask` is effectively inert). Access is
  governed by the share's NTFS/SMB **ACLs** the admin sets — the `include_repo`/
  `include_user` path composition still applies, so the logs still separate
  cleanly per repo and per user.

### `commit` — commit metadata

| Field | What it does | Default |
|---|---|---|
| `commit.co_author` | The `Co-Authored-By:` trailer added to agent-authored commits. An empty string opts out of the trailer entirely. | (the installing agent's identity) |

### `agents` — subagent floor

| Field | What it does | Default |
|---|---|---|
| `agents.min_model` | The minimum model any subagent may be dispatched on — **enforced** by a hook that denies a below-floor dispatch. A literal model id (e.g. `claude-sonnet-4-6`) sets a fixed floor; the sentinel `auto` (or `inherit`) floors at the session's current model. | `auto` |

### `cleanup` — branch cleanup

| Field | What it does | Default |
|---|---|---|
| `cleanup.protected_branches` | Branch names `/cleanup-merged` must never delete (exact match). | `[]` |
| `cleanup.long_running_patterns` | **Deprecated** — superseded by `protected_branches`. | `[]` |

### `output` — where artifacts go (migration-managed)

These point the plan, issue, and report directories somewhere other than their
legacy locations. They are special: **only `/update-zskills --migrate-paths`
writes them**, all-or-nothing, and their *absence is meaningful* — it preserves
the legacy layout. Don't add them by hand (adding one without moving files
strands artifacts).

| Field | Points at | When absent (legacy) |
|---|---|---|
| `output.plans_dir` | User-curated plans (e.g. `docs/plans`). | `plans/` |
| `output.issues_dir` | Issue trackers (e.g. `docs/issues`). | `plans/` |
| `output.reports_dir` | Agent work-trail reports (e.g. `docs/reports`). | `.zskills/audit` |

The `.zskills/` runtime subtree (tracking markers, audit dir, dev-server
pid/log) is **not** configurable — those paths are fixed.

### Top-level fields

| Field | What it does | Default |
|---|---|---|
| `project_name` | Human-readable name used in PR titles, reports, worktree path stems, and log-dir names. | `""` |
| `timezone` | IANA timezone for report and marker timestamps (e.g. `America/New_York`). | see [Lane differences](#lane-differences) |
| `zskills_version` | The installed-version fingerprint, written by `/update-zskills` and read by `/briefing` to flag when a newer zskills is available. Don't hand-edit — it'd produce a false "up to date" or "stale" signal. | `""` |

### Reserved (declared but not yet wired)

`ci.auto_fix` and `ci.max_fix_attempts` appear in the schema and the default
config, but no skill reads them at runtime today — the PR fix-cycle currently
uses a fixed limit of two attempts. Treat them as reserved for a future
release; changing them has no effect yet.

## Landing & protection

`execution.landing` and `execution.main_protected` are the two knobs that
define how changes reach `main`. Because they belong together, `/update-zskills`
sets them as a matched **preset** rather than expecting you to edit each one:

| Preset (`/update-zskills <preset>`) | `landing` | `main_protected` |
|---|---|---|
| `cherry-pick` (default) | `cherry-pick` | `false` |
| `locked-main-pr` | `pr` | `true` |
| `direct` | `direct` | `false` |

Run e.g. `/update-zskills locked-main-pr` to switch — it updates both fields
through the supported path. (A bare preset is a pure landing-mode switch; it
touches nothing else.) For a fuller explanation of what each mode means, see
[Landing mode](installing-zskills.md#landing-mode) in the install guide.

When `main_protected` is `true`, the protection is **enforced**, not advisory —
but it gates **agents, not the watching human**. The exact contract:

> **`main_protected:true` = block AUTONOMOUS/unwatched direct-to-main (force
> agents through the worktree/PR flow); attended/watched humans are
> UNRESTRICTED and SILENT, regardless of `main_protected`'s value.**

So an autonomous/unwatched session is blocked from editing, committing,
cherry-picking, or pushing directly to `main`, exactly as before; an
attended human running the same operations sees **no warning and no block**
even under `main_protected:true` (git and the permission-prompt layer cover
attended safety). This is the [enforcement model](#hook-toggles--the-enforcement-model)
applied to the main-protection checks. A project that wants the old
hard-deny-even-attended behavior on any of these sets the matching
`hooks.main_protection.*` toggle to `"block"`; one that wants the old
warn-when-watched nag sets it to `"warn"`. When dirty `main` work needs to
move off `main`, the sanctioned escape is the **move-to-worktree** helper
(it carries the dirt into a worktree without `git stash`, which stays
hard-denied).

## Hook toggles & the enforcement model

zskills ships a set of safety hooks that block dangerous operations. The
whole system follows one teachable rule:

> **Stay QUIET when watched (no nagging); BLOCK when no one's watching;
> coaching is OPT-IN; projects/users override per-check.**

**Zero-config quiet is the headline.** On a fresh install with **no config
of any kind** (no project `.claude/zskills-config.json`, no
`~/.claude/zskills-config.json`), an **attended** human is nagged about
**nothing** on a routine git workflow — no warnings *and* no blocks on
`git add .`, commit, push to a `main_protected:true` main, or editing
`main` in place. The IDENTICAL commands in an **autonomous/unwatched**
session are denied exactly as they always were. You do not write a single
line of config to get the quiet attended experience — it is the shipped
built-in default. (There is one named exception, the config-tamper gate;
see below.)

### Watched vs. autonomous

A hook decides whether it is *watched* or *autonomous* from one signal
(no TTY sniffing, no env vars, no transcript heuristics):

- **Autonomous (enforce)** — the permission-mode field is
  absent/unrecognized (fail-safe → enforce), OR a zskills pipeline is LIVE
  (a `.zskills/tracked` marker at the effective local root or the main
  root, or a fresh `.zskills/inflight/` sentinel). Demotable checks
  **BLOCK** here.
- **Watched** — everything else (a normal attended session in `default`,
  `acceptEdits`, `plan`, or `bypassPermissions` permission mode with no live
  pipeline marker). `bypassPermissions` (a human running
  `--dangerously-skip-permissions`) is treated as ATTENDED — it is a
  permission-convenience flag, not an attendance signal — so it does not by
  itself classify the session as autonomous; genuine autonomy under bypass
  is still caught by the live-pipeline arm, and a project that wants hard
  enforcement regardless keeps it via the per-check `"block"` toggle.
  A demotable check is **SILENT by shipped default** — it does nothing (no
  warning, no block; the permission prompt the session would normally get
  still fires from the harness). Coaching is opt-in: set the per-check
  toggle to `"warn"` to restore warn-when-watched.

### The `hooks` block — per-check toggles (project-only)

A `hooks` block in `.claude/zskills-config.json` tunes each check. It is
**project-only** — there is no user-tier hook config, and no posture knob
(the quiet posture is the built-in default, not a setting). The block has
**seven groups**, named exactly:

`git_destructive`, `fs_destructive`, `process_kill`, `git_discipline`,
`main_protection`, `pr_discipline`, `tracking`.

Each group has an `enabled` boolean (a **ceiling** — `enabled: false`
turns the whole group off) plus per-check **tristate** toggles:

- `"block"` — strict: deny even when watched.
- `"warn"` — opt-in coaching: warn-when-watched (and still allow); the
  warning reaches the human and the command runs.
- `"off"` — silent: never warns, never blocks.

An explicit per-check value is **always honored**, in both directions — a
project that commits `reset_hard: "warn"` to its reviewed config made a
deliberate choice, and a `"block"` on a normally-demotable check makes it
strict. The class only sets the **unset** default:

- **`hard`** checks → **block always** (the predicate never demotes them):
  the destructive-git, filesystem-destructive, process-kill, and a few
  discipline checks (`no_verify`, `stale_skill_version`, `cron_invalid`,
  `direct_gh_pr`).
- **`demotable`** checks → **silent-when-watched / block-when-autonomous**:
  the git-discipline coaching checks, the main-protection checks, and the
  tracking-discipline gates.

**Fail-closed.** A missing config, an unparseable config, or an
unavailable Python interpreter all fall back to the shipped defaults
(hard checks block; demotable checks follow the watched/autonomous
predicate). Nothing ever errors a hook.

### Every message names its own switch

Each warn/deny message ends with its toggle path and effective source, e.g.

```
[hooks.git_discipline.git_add_all — block|warn|off in .claude/zskills-config.json; currently: attended default (silent)]
```

so when a check fires you can see exactly which key to set to change it.

### The config-tamper gate (the one named exception)

Editing the **main** config's `hooks` block is itself gated by
`hooks.main_protection.config_hooks_tamper`. It is the **one demotable
check that is NOT silent when watched**: its shipped watched default is
**`warn`** (visible, non-blocking), because disarming the protection
system itself is durable and cross-session and must never happen
invisibly. An autonomous session that rewrites the toggle file is
**denied**; a watched session is **warned and allowed**. A project that
finds even the warn too noisy sets `config_hooks_tamper` to `"off"`; one
wanting hard-deny-even-attended sets `"block"`.

The tamper gate has two self-protections: it is **exempt from its group's
`enabled` ceiling** (a `main_protection.enabled: false` write cannot
silently take the tamper check down with the group), and flipping the
tamper toggle's own value is itself a tamper-gated write evaluated under
the *pre-write* config (so an autonomous session cannot disarm it — the
deny fires before the new value exists). **Threat model, stated honestly:**
this gate is **anti-casual, not anti-adversarial**. Toggle reads are
**main-root-only** — a worktree's checkout copy of the config is never
consulted for toggles, so a worktree-local config edit cannot disarm a
toggle — but a Bash-mediated write that never names the config file as a
literal destination (variable destinations, programmatic writes) is not
caught. Those writes stay visible in the session transcript, and project
review owns the committed config.

### Claim-gate caveat (two watched sessions)

The tracking claim gates (`issue_unclaimed`, `plan_unclaimed`) are
demotable: an autonomous session is denied a foreign-held work item, but
two **concurrently watched** sessions are both silent by default, so the
same item can be double-claimed (no single human sees both sides). A
project that wants hard cross-session exclusion sets
`hooks.tracking.issue_unclaimed` / `hooks.tracking.plan_unclaimed` to
`"block"`.

### Worked example

```json
"hooks": {
  "git_destructive": { "enabled": true },
  "git_discipline": {
    "git_add_all": "warn",
    "test_pipe": "off"
  },
  "main_protection": {
    "push_to_main": "block",
    "config_hooks_tamper": "warn"
  },
  "tracking": {
    "issue_unclaimed": "block"
  }
}
```

This project opts into coaching on `git add .` (warn-when-watched), silences
the test-pipe nag entirely, hard-denies pushes to `main` even for an
attended human, keeps the tamper warn, and enforces strict cross-session
issue claiming.

### The 37 toggle keys

Every check, by its full `hooks.<group>.<check>` path:

- **`git_destructive`** — `git_destructive.stash_drop`,
  `git_destructive.stash_write`, `git_destructive.checkout_discard`,
  `git_destructive.restore_discard`, `git_destructive.switch_discard`,
  `git_destructive.clean_force`, `git_destructive.reset_hard`
- **`process_kill`** — `process_kill.kill_9`, `process_kill.fuser_k`,
  `process_kill.xargs_kill`, `process_kill.kill_substitution`
- **`fs_destructive`** — `fs_destructive.rm_recursive`,
  `fs_destructive.find_delete`, `fs_destructive.rsync_delete`,
  `fs_destructive.xargs_destructive`, `fs_destructive.zskills_tree_delete`,
  `fs_destructive.clear_tracking_agent`
- **`git_discipline`** — `git_discipline.git_add_all`,
  `git_discipline.no_verify`, `git_discipline.logs_add_all`,
  `git_discipline.test_pipe`, `git_discipline.full_cmd_unset`,
  `git_discipline.tests_not_run`, `git_discipline.ui_unverified`,
  `git_discipline.stale_skill_version`
- **`main_protection`** — `main_protection.push_to_main`,
  `main_protection.commit_on_main`, `main_protection.cherry_pick_on_main`,
  `main_protection.main_edit`, `main_protection.config_hooks_tamper`
- **`tracking`** — `tracking.requires_unfulfilled`,
  `tracking.step_unverified`, `tracking.step_unreported`,
  `tracking.issue_unclaimed`, `tracking.plan_unclaimed`,
  `tracking.cron_invalid`
- **`pr_discipline`** — `pr_discipline.direct_gh_pr`

(The subagent-model floor is governed by `agents.min_model`, not a
`hooks.*` key — see the [`agents`](#agents--subagent-floor) reference.)

## How values resolve

Every field first resolves through [the config cascade](#the-config-cascade)
(project > user > built-ins). On top of that, resolution differs by field:

- **Most string settings** (`testing.*`, `dev_server.cmd`, `commit.co_author`,
  `timezone`) resolve through the cascade; the ones with no sane universal
  value (test and dev-server commands, the co-author trailer) have **no
  built-in default** and stay empty when no tier sets them — the consuming
  skill handles empty explicitly rather than guessing.
- **A few settings honor an environment override** for one-off runs:
  - `logging.dir` (the composition base) ← `ZSKILLS_LOG_DIR` env > config > the per-OS cache base; then composed with the optional `<repo>`/`<user>` segments. `ZSKILLS_LOG_USER` similarly overrides the runtime-resolved `<user>` segment.
  - the dev port ← `DEV_PORT` env > a `scripts/dev-port.sh` stub > `dev_server.default_port` (main repo) > a per-worktree hash port.
- **The enforced keys** (`main_protected`, `agents.min_model`,
  `logging.enabled`) are re-read from the config at runtime by their hooks, so
  editing them takes effect on the next tool call — no reinstall needed.

The five cascade-v2 keys and the `hooks` block resolve specially:

| Field | How it resolves |
|---|---|
| `execution.landing` | Plain cascade: project > user > built-in (`direct`/`cherry-pick` per lane). |
| `execution.branch_prefix` | Plain cascade: project > user > built-in (`feat/`). |
| `execution.max_concurrent_worktrees` | Plain cascade: project > user > built-in (`3`). |
| `execution.main_protected` | **Raise-only floor** — `true` from *either* tier wins; the user tier can raise a project's `false` to protected but can never lower a project's `true`. Read at the local toplevel by the gating hooks. |
| `agents.min_model` | **Raise-only floor** — the stricter model tier wins; a tie resolves to the project value. The user tier can raise the floor, never lower it. |
| `hooks.*` (toggles) | **Project-only, main-root-only.** Read exclusively from `<main root>/.claude/zskills-config.json` (never a worktree copy, never the user tier) by the enforcement hooks; missing/unparseable → shipped defaults (fail-closed). See [Hook toggles & the enforcement model](#hook-toggles--the-enforcement-model). |

## Lane differences

A consumer installs zskills through exactly one lane, and the two seed a fresh
config slightly differently:

| | `/update-zskills` lane | Plugin lane |
|---|---|---|
| When written | At `install` time | At `/zs:update-zskills` init, **only if you accept the offer** (decline = no file; built-in defaults apply) |
| Values | Auto-detected where possible (test command, timezone) | The built-in defaults (timezone `UTC`, landing `direct`) for you to tune |
| Default preset | `cherry-pick` (unprotected) | `direct` (unprotected) |

Either way, the file is yours to refine afterward — the seed is only a starting
point, and an existing config is never overwritten.

## What not to hand-edit

Most fields are safe to edit directly. These few are managed for you, and
editing them by hand causes drift:

- **`execution.landing` / `execution.main_protected`** — change them with a
  `/update-zskills <preset>`, not by hand, so the install stays consistent.
- **`output.plans_dir` / `issues_dir` / `reports_dir`** — only
  `/update-zskills --migrate-paths` may write these (it also moves the files).
- **`zskills_version`** — written from the source repo's release tag; a manual
  value produces a false update signal.

On the `/update-zskills` lane, editing the config through Claude Code also
triggers a "re-render needed" warning — run `/update-zskills --rerender`
afterward to refresh the rendered rules file. (On the plugin lane the rules
are delivered fresh each session, so there is nothing to re-render.)

## See also

- [Installing zskills](installing-zskills.md) — first-time setup, the
  [Landing mode](installing-zskills.md#landing-mode) explainer, and how to
  [switch installs](installing-zskills.md#switching-installs).
- [`/update-zskills`](../skills/update-zskills.md) — the skill that writes and
  maintains this file.
- [`config/zskills-config.schema.json`](../../config/zskills-config.schema.json)
  — the authoritative schema.
