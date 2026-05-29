# Installing zskills — the two install lanes

zskills ships via **two permanent, first-class install lanes**. Neither is
deprecated; both are supported indefinitely. This doc is the full side-by-side
comparison so you can pick one (or run both — see [Known tradeoffs](#known-tradeoffs)).

- **Plugin lane** — Claude Code's native marketplace/plugin mechanism. One
  command to install, one command to update, and skills show up in the slash
  menu under a `/zs:` prefix.
- **`/update-zskills` lane** — the bespoke installer that mirrors the skill
  source into your repo's `.claude/`, copies the hooks, registers them in
  `.claude/settings.json`, and renders the managed CLAUDE.md rules. Install
  state is plain tracked files in your repo.

For the **default recommendation** (which lane to pick when you have no strong
preference), jump to [Default recommendation](#default-recommendation).

## Side-by-side comparison

| Surface | `/update-zskills` lane | Plugin lane |
|---|---|---|
| Install command | `/update-zskills install ...` | `/plugin marketplace add zeveck/zskills && /plugin install zs@zskills` |
| Slash prefix | bare (`/run-plan`, `/quickfix`) | `/zs:` (`/zs:run-plan`, `/zs:quickfix`) |
| Skills location | `.claude/skills/<name>/` | `${CLAUDE_PLUGIN_ROOT}/skills/<name>/` |
| Hooks location | `.claude/hooks/<name>.sh` | `${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh` (plus 4 materialised under `.claude/`) |
| Rules file | `.claude/rules/zskills/managed.md` (rendered by `/update-zskills`) | `.claude/rules/zskills/managed.md` (materialised by the SessionStart hook) |
| Updates | `/update-zskills install` (re-fetch + re-mirror) | `/plugin marketplace update` |
| Marketplace name / Plugin name | n/a | `zskills` / `zs` |
| `claude` CLI required on the host? | no | yes |
| Install state checkable via file presence? | yes (tracked files in `.claude/`) | partial (only the 5 materialised artifacts; the rest lives under `${CLAUDE_PLUGIN_ROOT}`) |

## Install

### Plugin lane

From inside a Claude Code session in your project:

```
/plugin marketplace add zeveck/zskills
/plugin install zs@zskills
```

The first command registers the `zskills` marketplace (the
`.claude-plugin/marketplace.json` manifest in the zskills repo root). The
second installs the `zs` plugin (the full distribution). Restart the session
when prompted so the plugin's hooks load.

To add the block-diagram add-on (3 extra skills) install the `zsbd` plugin
from the same marketplace:

```
/plugin install zsbd@zskills
```

On the first SessionStart after install, a hook materialises five artifacts
into your repo's `.claude/` that a plugin cannot write at install time:

1. `.claude/agents/verifier.md`
2. `.claude/agents/implementer.md`
3. `.claude/hooks/inject-bash-timeout.sh`
4. `.claude/hooks/verify-response-validate.sh`
5. `.claude/rules/zskills/managed.md` (rendered from the shipped `CLAUDE_TEMPLATE.md`)

These five paths are **plugin-managed** — see [.gitignore guidance](#gitignore-guidance).

### `/update-zskills` lane

Clone the repo, copy the skills, and run `/update-zskills`:

```bash
git clone https://github.com/zeveck/zskills.git /tmp/zskills
mkdir -p .claude/skills
cp -r /tmp/zskills/skills/* .claude/skills/
```

Then in a Claude Code session:

```
/update-zskills install
```

`/update-zskills` creates `.claude/zskills-config.json` with auto-detected
project settings, installs hooks and scripts into `.claude/`, registers hooks
in `.claude/settings.json`, renders `CLAUDE_TEMPLATE.md` →
`.claude/rules/zskills/managed.md`, and reports any gaps. See the repo
[`README.md`](../README.md) for the full first-run flow (including the
landing-mode prompt). Add the block-diagram add-on with
`/update-zskills install --with-block-diagram-addons`.

## Slash-prefix expectations

- **`/update-zskills` lane:** skills are invoked bare — `/run-plan`,
  `/quickfix`, `/fix-issues`, etc.
- **Plugin lane:** Claude Code namespaces plugin-provided skills under the
  plugin name, so the slash menu and typed invocations use the `/zs:` prefix —
  `/zs:run-plan`, `/zs:quickfix`, `/zs:fix-issues`. The `zsbd` add-on skills
  are similarly namespaced under `/zsbd:`.

This prefix difference is purely the **typed-invocation surface**. Skill-tool
dispatch (one skill calling another) and cron auto-fire are prefix-agnostic —
see [Known tradeoffs](#known-tradeoffs) for the one place this difference
leaks into the UX.

## Update workflow

| Lane | Update command | What it does |
|---|---|---|
| Plugin | `/plugin marketplace update` | Re-fetches the marketplace's tracked ref and pulls the new plugin tree. The SessionStart materialiser re-writes the 5 `.claude/` artifacts on next session start (only files still carrying the `zskills-materialised:` sentinel are overwritten — your edits are never clobbered). |
| `/update-zskills` | `/update-zskills install` | Re-fetches the source tree, re-mirrors changed skills/hooks into `.claude/`, and re-renders `managed.md`. Existing config is preserved (no re-prompt). |

## Default recommendation

Both lanes are first-class; this recommendation is for the indecisive reader,
not a constraint.

- **Interactive workflows (default): plugin lane.** One-command install and
  one-command updates, marketplace-native, and the slash menu surfaces the
  `/zs:` prefix so discovery is built in.
- **Headless CI consumers: `/update-zskills` lane.** The plugin lane requires
  the `claude` CLI on your runners; the `/update-zskills` lane does not. Its
  install state is plain tracked files, so CI can verify presence with a file
  check rather than a CLI round-trip.
- **Power users: either.** The difference is cosmetic — pick by preference.

### Tradeoff matrix

| Dimension | Plugin lane | `/update-zskills` lane |
|---|---|---|
| Install effort | Two slash commands | Clone + copy + `/update-zskills install` |
| Update effort | `/plugin marketplace update` | `/update-zskills install` |
| `claude` CLI required on host | Yes | No |
| Works on headless CI runners w/o `claude` | No | Yes |
| Install state in git | 5 materialised artifacts only (rest under `${CLAUDE_PLUGIN_ROOT}`) | Full mirror tracked in `.claude/` |
| Slash prefix | `/zs:` (menu discovery) | bare |
| Version pinning | marketplace `source.sha` / `source.ref` (see below) | clone a tag, re-copy |
| Reviewable diff of the skill source in-repo | No (lives outside the repo) | Yes (mirror is tracked) |

## Pin-by-version idiom

Each release pushes **both** a moving `prod/main` ref and a parallel
`prod/<version>` tag (e.g. `prod/2026.05.1`). Unpinned consumers track the
moving `prod/main` window; consumers who want reproducibility pin to a
specific version.

The default marketplace entry tracks the moving window:

```json
{ "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "ref": "prod/main" } }
```

To **pin to a specific release**, edit your marketplace's `zs` entry to either:

- Override `source.ref` to the version tag:

  ```json
  { "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "ref": "prod/2026.05.1" } }
  ```

- Or pin `source.sha` to the exact commit:

  ```json
  { "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "sha": "<commit-sha>" } }
  ```

The `github` source schema accepts `repo`, `ref?`, and `sha?` — there is no
`path` field. The co-located `zsbd` add-on ships as the relative-path source
`./block-diagram` inside the same marketplace repo, so it follows the
marketplace's checked-out ref by construction; no separate `ref` is needed (or
supported) on the relative-path entry. Pinning the `zs` entry's ref/sha
therefore pins `zsbd` to the same snapshot.

For how releases produce these refs, see
[`RELEASING.md`](../RELEASING.md) (the dual-path release flow:
`build-prod.sh` for the legacy mirror, `build-plugin-release.sh` for the
plugin tree, both targeting `prod/main` plus a `prod/<version>` tag).

## `.gitignore` guidance

The right guidance depends on your lane.

- **Plugin-lane consumers — gitignore the 5 materialised paths.** They are
  plugin-managed (re-written by the SessionStart materialiser on each upgrade),
  so tracking them in your repo only produces churn. Add to `.gitignore`:

  ```gitignore
  # zskills plugin-materialised artifacts (managed by the zs plugin)
  .claude/agents/verifier.md
  .claude/agents/implementer.md
  .claude/hooks/inject-bash-timeout.sh
  .claude/hooks/verify-response-validate.sh
  .claude/rules/zskills/managed.md
  ```

- **`/update-zskills`-lane consumers — leave the paths tracked.** Under this
  lane those files (and the rest of the `.claude/` mirror) **are** your install
  state. Tracking them in git is correct: your repo is the source of truth for
  which skill/hook versions you have installed, and the mirror is reviewable in
  a diff.

If you run **both** lanes (see below), follow the `/update-zskills`-lane
guidance — the mirror wins, and the materialiser defers to it (it detects the
`/update-zskills` install lane and exits without writing).

## Marketplace promotion / activation

Activating the public marketplace (so `/plugin marketplace add zeveck/zskills`
resolves) and promoting a release to it are **human-gated publish actions**
performed by maintainers — not part of consumer onboarding. The mechanics live
in [`RELEASING.md`](../RELEASING.md):

- The release pushes the prod-stripped plugin tree to `prod/main` plus a
  `prod/<version>` tag via `scripts/build-plugin-release.sh --push` (a
  deliberate, human-gated step — the dry build never pushes).
- The `.claude-plugin/marketplace.json` manifest at the repo root is what
  `/plugin marketplace add zeveck/zskills` reads; its `zs` entry's
  `source.ref` (default `prod/main`) determines which release consumers track.

Consumers do not perform any activation step — they only run the install
commands above.

## Known tradeoffs

### Bare-slash prose UX gap (plugin lane)

Skill bodies reference sibling skills by their **bare** slash name (e.g. "then
run `/quickfix`" or "this dispatches `/land-pr`"). Under the plugin lane the
user-typed invocation surface is prefixed (`/zs:quickfix`, `/zs:land-pr`), so
the prose and the typed command don't textually match. This is a **prose/UX
gap only** — every functional path still works:

- **Skill-tool dispatch is prefix-agnostic.** When one skill dispatches
  another via the Skill tool (the mechanism behind "this dispatches
  `/land-pr`"), resolution is by skill name, not by the typed slash string. The
  `/zs:` prefix is a typed-invocation affordance; it does not change how skills
  dispatch each other. Cross-skill chains work identically in both lanes.
- **Cron auto-fire handles both forms.** Cron-fired prompts (`Run /fix-issues
  ...`) are recognized by an OR-match that accepts both the bare and the
  `/zs:`-prefixed skill name, so scheduled/auto-fired runs work under either
  lane without the user adjusting the cron prompt.
- **Only the typed-slash invocation needs a mental swap.** The single place
  the gap surfaces is a human reading skill-body prose that says `/foo` and
  then typing it: under the plugin lane they must type `/zs:foo`. The slash
  menu shows the correct `/zs:`-prefixed names, so this is a momentary
  translation, not a broken path.

If the prefix translation is a recurring friction for your team, the
`/update-zskills` lane (bare prefixes, matching the prose verbatim) is the
lower-friction choice — which is exactly the kind of preference the
[default recommendation](#default-recommendation) leaves to the reader.

## Switching lanes

Already installed via one lane and want to move to the other? See
[`PLUGIN_MIGRATION.md`](PLUGIN_MIGRATION.md) — `scripts/switch-install-path.sh`
(also reachable as `/update-zskills --switch-install-path={to-plugin|to-update-zskills}`)
is the bidirectional consolidation tool, with Abort/Rollback documented for
both directions.
