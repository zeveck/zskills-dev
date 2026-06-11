# Installing zskills

There are two ways to install zskills. Pick one — you can't run both at the
same time.

→ **[Plugin install](#plugin-install)** (recommended for new installs) — two
  commands inside a Claude Code session, plus a one-time `/zs:update-zskills`
  setup. Updates come from the marketplace, the plugin writes nothing into
  your repo beyond that setup's footprint, and the slash menu lists the
  skills under a `/zs:` prefix.

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
`zs` plugin (the full distribution).

Then **restart Claude Code (or run `/clear`) so the plugin's skills and hooks
load**, and run the one-time setup:

```
/zs:update-zskills
```

This is the explicit **init** — it adds one `.zskills/` umbrella line to your
`.gitignore`, offers (but doesn't require) a project config, verifies the
install, and writes the gitignored `.zskills/init-done` marker. It also
reports whether `git`, Python, and `gh` are present. Until you run it, a
one-line greeting on startup reminds you, and the skills that write project
state are blocked (read-only skills work immediately).

> **If the install fails to clone with a git SSH error** — something like
> `git@github.com: Permission denied (publickey)` followed by
> `fatal: Could not read from remote repository` — your git is configured to
> reach GitHub over **SSH** (usually a global `insteadOf` rewrite), but the
> plugin clones over **HTTPS**. Tell Claude *"configure git to use HTTPS instead
> of SSH so the install works"* and re-run `/plugin install zs@zskills`.

**The plugin writes nothing into your project by itself.** Skills, hooks, the
verifier/implementer agents, and the agent rules all live in (and run from)
the plugin's own tree — `git status` in your project stays clean across
sessions. The only project-side footprint is what init creates: the
`.gitignore` line, the gitignored `.zskills/` runtime state, and — only if
you say yes at init — `.claude/zskills-config.json` plus its schema sibling.

The config is **optional**. Without one, zskills runs on built-in defaults:
work lands in **`direct`** mode (`execution.landing: direct`,
`main_protected: false` — agents work and commit directly on `main`, the
simplest default for solo work), timezone `UTC`, and no project test commands.
A config lets you set test commands, the dev-server command, landing mode,
and more (see [Configuring zskills](zskills-config.md)). To switch to a
review workflow (a worktree + pull request, with `main` locked), see
[Landing mode](#landing-mode).

**Install scope — prefer project-scoped enablement.** When the CLI asks where
to enable the plugin (or when you pass a scope flag), choose the **project**
scope. A user-scope install enables zskills in *every* project you open: its
agent-rules context (~15KB) and the setup greeting then appear in projects
that never asked for zskills. Nothing is written into those projects — the
trade is context noise, not files — but project-scoped enablement avoids it
entirely.

## `/update-zskills` install

Clone the repo, copy the skills into `.claude/skills/`, then run the installer
in a Claude Code session:

```bash
git clone https://github.com/zeveck/zskills.git /tmp/zskills
mkdir -p .claude/skills
cp -r /tmp/zskills/skills/* .claude/skills/
```

If `git clone` fails with the same `git@github.com: Permission denied` SSH error
as under [Plugin install](#plugin-install), the cause and fix are identical —
point git at HTTPS, then retry.

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
| Plugin | `/plugin marketplace update` | Pulls the latest plugin from the marketplace. Everything runs from the plugin's own tree, so there are no project files to refresh. (An optional follow-up `/zs:update-zskills` re-verifies the install and updates the recorded version.) |
| `/update-zskills` | `/update-zskills install` | Re-fetches the source, copies changed skills and hooks into `.claude/`, and regenerates the rules file. Your existing config is kept. |

## Comparison

| | Plugin install | `/update-zskills` install |
|---|---|---|
| Install | `/plugin marketplace add zeveck/zskills` then `/plugin install zs@zskills`, then one-time `/zs:update-zskills` | Clone + copy + `/update-zskills install` |
| Update | `/plugin marketplace update` | `/update-zskills install` |
| Slash prefix | `/zs:` (`/zs:run-plan`) | bare (`/run-plan`) |
| Needs the `claude` CLI on the host | Yes | No |
| Skill source in your repo | No (managed by the plugin) | Yes (copied into `.claude/`, shows in a diff) |
| Files in your repo | `.gitignore` line + gitignored `.zskills/` state + optional config | The full `.claude/` install (skills, hooks, agents, rules, config) |

## Slash prefix

The plugin install lists skills under a `/zs:` prefix — you type `/zs:run-plan`,
`/zs:do`, and so on, and the slash menu shows the prefixed names. The
`/update-zskills` install uses the bare names: `/run-plan`, `/do`.

This only affects what you type. When one skill triggers another, or when a
scheduled "Run /fix-issues ..." prompt fires, both the bare and the `/zs:` form
are recognized, so those paths work the same either way. The one place the
prefix shows is reading skill text that says `/do` and then typing it: on
the plugin install you type `/zs:do`. If that translation is a recurring
annoyance for your team, the `/update-zskills` install (bare names, matching the
text) is the lower-friction choice.

## `.gitignore` guidance

What to track depends on your install.

- **Plugin install — nothing to do.** Init already added the one line that
  matters (`.zskills/` — the runtime-state umbrella) to your `.gitignore`.
  There are no plugin-managed files in your repo to ignore. If you accepted a
  config at init, `.claude/zskills-config.json` (and its schema sibling) is
  yours — tracking it in git is recommended so your team shares the settings.

- **`/update-zskills` install — keep the install tracked.** Under this install
  the `.claude/` copy (skills, hooks, agents, rules, config) *is* your install
  state. Tracking it in git is correct: your repo records which skill and hook
  versions you have, and the copy is reviewable in a diff. The installer adds
  the same `.zskills/` gitignore umbrella for the runtime state.

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

Already installed one way and want to switch? **Uninstall one, install the
other** — there is no in-place switch.

- **Plugin → `/update-zskills`:** run `/plugin uninstall zs@zskills`, restart
  Claude Code, then follow [`/update-zskills` install](#update-zskills-install).
  Your `.claude/zskills-config.json` and `.zskills/` runtime state carry over
  untouched.
- **`/update-zskills` → plugin:** remove the installed copies (the zskills
  skills under `.claude/skills/`, the zskills hooks under `.claude/hooks/` and
  their `.claude/settings.json` registrations, the zskills agents under
  `.claude/agents/`, and `.claude/rules/zskills/managed.md` — leave your own
  files alone), then follow [Plugin install](#plugin-install). Keep your
  config; the plugin reads the same `.claude/zskills-config.json`.

Running both at once is not a supported state — `/update-zskills`'s verifier
flags it, and `/update-zskills install` refuses to re-create the mirror on a
plugin-lane project.
