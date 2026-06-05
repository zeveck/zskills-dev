# Configuring zskills

Every zskills install is steered by one file: `.claude/zskills-config.json`.
It tells the skills, hooks, and helper scripts how *your* project works — how
to run tests, how changes reach `main`, what the dev server command is, which
timezone to stamp reports in, and more. This guide explains where the file
comes from, what every field does, and which fields you should never hand-edit.

You rarely write this file by hand. `/update-zskills` creates and maintains it
for you (and on the plugin lane it's seeded automatically on first session).
Reach for this guide when you want to understand a setting, change one
deliberately, or debug why a skill behaved the way it did.

## Where it lives

| File | Role |
|---|---|
| `.claude/zskills-config.json` | Your project's settings (this guide). |
| `.claude/zskills-config.schema.json` | The JSON Schema the config validates against — the authoritative list of every key and default. Editors that honor `$schema` will autocomplete and lint against it. |

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
- **Plugin lane** — plugins can't write files at install time, so a
  `SessionStart` hook **seeds** a default config the first time you open the
  project — but only when the file is *absent*. An existing config is never
  clobbered. (The plugin seed defaults differ slightly; see
  [Lane differences](#lane-differences) below.)

A handful of fields are managed entirely by `/update-zskills` and should not be
hand-edited — see [What not to hand-edit](#what-not-to-hand-edit).

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
| `execution.main_protected` | When `true`, agents cannot edit, commit, cherry-pick, or push to `main` — every change must go through a worktree and PR. **Enforced** by hooks, not just convention. | `false` |
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

When `main_protected` is `true`, the protection is **enforced**, not advisory:
separate hooks deny edits, commits/cherry-picks, and pushes that target `main`.
This is what forces every change through a worktree and a PR rather than letting
an agent edit `main` in place.

## How values resolve

There is no single "env > config > default" rule — resolution differs by field:

- **Most string settings** (`testing.*`, `dev_server.cmd`, `commit.co_author`,
  `timezone`) resolve to the config value with **no opinionated default**: when
  absent, the consuming skill applies its own fallback (for example, timezone
  falls back to UTC at the point of use). This is why an unset field is simply
  empty rather than guessed.
- **A few settings honor an environment override** for one-off runs:
  - `logging.dir` (the composition base) ← `ZSKILLS_LOG_DIR` env > config > the per-OS cache base; then composed with the optional `<repo>`/`<user>` segments. `ZSKILLS_LOG_USER` similarly overrides the runtime-resolved `<user>` segment.
  - the dev port ← `DEV_PORT` env > a `scripts/dev-port.sh` stub > `dev_server.default_port` (main repo) > a per-worktree hash port.
- **The enforced keys** (`main_protected`, `agents.min_model`,
  `logging.enabled`) are re-read from the config at runtime by their hooks, so
  editing them takes effect on the next tool call — no reinstall needed.

## Lane differences

A consumer installs zskills through exactly one lane, and the two seed a fresh
config slightly differently:

| | `/update-zskills` lane | Plugin lane (auto-seed) |
|---|---|---|
| When written | At `install` time | First `SessionStart`, only if absent |
| `timezone` | `America/New_York` | `UTC` |
| Default preset | `cherry-pick` (unprotected) | `locked-main-pr` (protected) |

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

Editing the config through Claude Code also triggers a "re-render needed"
warning, because some values are baked into your generated project rules — run
`/update-zskills --rerender` afterward to refresh them.

## See also

- [Installing zskills](installing-zskills.md) — first-time setup and the
  [Landing mode](installing-zskills.md#landing-mode) explainer.
- [Switching install lanes](switching-install-lanes.md) — moving between the
  plugin and `/update-zskills` lanes.
- [`/update-zskills`](../skills/update-zskills.md) — the skill that writes and
  maintains this file.
- [`config/zskills-config.schema.json`](../../config/zskills-config.schema.json)
  — the authoritative schema.
