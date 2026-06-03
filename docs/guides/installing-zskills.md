# Installing zskills

There are two ways to install zskills. Pick one — you can't run both at the
same time.

→ **[Plugin install](#plugin-install)** (recommended for new installs) — two
  commands inside a Claude Code session. Updates come from the marketplace, and
  the slash menu lists the skills under a `/zs:` prefix.

→ **[`/update-zskills` install](#update-zskills-install)** — the original
  installer. Choose this if you want the bare slash names (`/run-plan` instead
  of `/zs:run-plan`), or want the skill source copied into your repo's
  `.claude/` so changes show up in a normal git diff.

Both produce the same running behavior. The differences are how you install and
update, the slash prefix, and whether the skill source lives in your repo. The
[comparison table](#comparison) lays them out side by side.

## Plugin install

From inside a Claude Code session in your project:

```
/plugin marketplace add zeveck/zskills
/plugin install zs@zskills
```

The first command registers the `zskills` marketplace; the second installs the
`zs` plugin (the full distribution). Restart the session when prompted so the
plugin's hooks load.

On the first session after install, the plugin writes a handful of files into
your project's `.claude/`: the two agent definitions (`.claude/agents/`), two
hook scripts (`.claude/hooks/`), and the agent-rules file
(`.claude/rules/zskills/managed.md`). These are plugin-managed — when you
upgrade, the plugin refreshes them. If you've edited one of these files
yourself, your edited copy is left alone. See
[`.gitignore` guidance](#gitignore-guidance) for whether to track them.

By default the plugin install lands work in **`locked-main-pr`** mode
(`execution.landing: pr`, `main_protected: true`): agents don't commit to
`main` directly — finished work ships as a pull request from a worktree on a
feature branch. To change it, see [Landing mode](#landing-mode).

## `/update-zskills` install

Clone the repo, copy the skills into `.claude/skills/`, then run the installer
in a Claude Code session:

```bash
git clone https://github.com/zeveck/zskills.git /tmp/zskills
mkdir -p .claude/skills
cp -r /tmp/zskills/skills/* .claude/skills/
```

```
/update-zskills install
```

`/update-zskills install` auto-detects your project's settings and writes them
to `.claude/zskills-config.json`, copies the safety hooks and helper scripts
into `.claude/`, registers the hooks in `.claude/settings.json`, and generates
the agent-rules file `.claude/rules/zskills/managed.md`. It starts by auditing
what's already on disk and reports the gaps before changing anything. See the
repo [README](../../README.md) for the full first-run walkthrough.

During install it asks how you want changes to land (see
[Landing mode](#landing-mode)). To skip the prompt, name the mode you want:
`/update-zskills install cherry-pick`.

## Landing mode

Landing mode is how an agent's finished work reaches your `main` branch. There
are three choices:

- **`locked-main-pr`** — Work happens in a worktree on a feature branch; once
  verified, the branch is pushed and a pull request is opened. `main` is locked,
  so agents can't commit or push to it directly. Pick this when you want code
  review on agent changes, or a checkpoint before `main` moves.

- **`cherry-pick`** — Work happens in a worktree on a feature branch; once a
  commit is verified, it's cherry-picked back to `main`. Lower ceremony than
  pull requests — good for solo work where you trust the verifier.

- **`direct`** — Agents work and commit directly on `main`, with no worktree and
  no landing step. Lowest ceremony, highest risk.

To change modes later, name the mode with no other argument:

```
/update-zskills <mode>
```

(On the plugin install, type `/zs:update-zskills <mode>`.) This changes only the
landing mode — your test commands, dev-server settings, and project name stay as
they were.

## Updating

| Install | Update command | What it does |
|---|---|---|
| Plugin | `/plugin marketplace update` | Pulls the latest plugin from the marketplace. On the next session, the five managed files are refreshed (any you've edited yourself are left alone). |
| `/update-zskills` | `/update-zskills install` | Re-fetches the source, copies changed skills and hooks into `.claude/`, and regenerates the rules file. Your existing config is kept. |

## Comparison

| | Plugin install | `/update-zskills` install |
|---|---|---|
| Install | `/plugin marketplace add zeveck/zskills` then `/plugin install zs@zskills` | Clone + copy + `/update-zskills install` |
| Update | `/plugin marketplace update` | `/update-zskills install` |
| Slash prefix | `/zs:` (`/zs:run-plan`) | bare (`/run-plan`) |
| Needs the `claude` CLI on the host | Yes | No |
| Skill source in your repo | No (managed by the plugin) | Yes (copied into `.claude/`, shows in a diff) |

## Slash prefix

The plugin install lists skills under a `/zs:` prefix — you type `/zs:run-plan`,
`/zs:quickfix`, and so on, and the slash menu shows the prefixed names. The
`/update-zskills` install uses the bare names: `/run-plan`, `/quickfix`.

This only affects what you type. When one skill triggers another, or when a
scheduled "Run /fix-issues ..." prompt fires, both the bare and the `/zs:` form
are recognized, so those paths work the same either way. The one place the
prefix shows is reading skill text that says `/quickfix` and then typing it: on
the plugin install you type `/zs:quickfix`. If that translation is a recurring
annoyance for your team, the `/update-zskills` install (bare names, matching the
text) is the lower-friction choice.

## `.gitignore` guidance

What to track depends on your install.

- **Plugin install — gitignore the plugin-managed files.** The plugin rewrites
  them on each upgrade, so tracking them only produces churn. Add to
  `.gitignore`:

  ```gitignore
  # zskills plugin-managed files
  .claude/agents/verifier.md
  .claude/agents/implementer.md
  .claude/hooks/
  .claude/rules/zskills/managed.md
  ```

  (If your project keeps its own hooks under `.claude/hooks/`, list the two
  zskills hook files individually instead of ignoring the whole directory.)

- **`/update-zskills` install — keep them tracked.** Under this install those
  files (and the rest of the `.claude/` copy) *are* your install state. Tracking
  them in git is correct: your repo records which skill and hook versions you
  have, and the copy is reviewable in a diff.

## Pinning to a release

By default the plugin install tracks the moving `main` window — each
`/plugin marketplace update` pulls the latest published tree. If you want a
reproducible install that does not move until you say so, pin your
marketplace's `zs` entry to a specific release. Releases are tagged with a
bare `<version>` of the form `YYYY.MM.N` (for example `2026.06.0`), so set
`source.ref` to that version tag:

```json
{ "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "ref": "2026.06.0" } }
```

Leave `ref` at `main` (or omit it) to keep tracking the latest release. The
`/update-zskills` install pins differently — clone the matching version tag and
re-copy the skills.

## Switching installs

Already installed one way and want to switch? See
[`switching-install-lanes.md`](switching-install-lanes.md), which walks through
the supported switch in both directions, including how to back out.
