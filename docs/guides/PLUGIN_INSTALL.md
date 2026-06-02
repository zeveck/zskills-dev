# Installing zskills

zskills ships via two permanent, first-class install lanes — both
supported indefinitely. Pick one and stick with it; running both at once
is not a supported end-state.

→ **[Plugin lane](#plugin-lane)** (recommended for new installs) — one command in
  your Claude Code session, marketplace-native updates, slash menu shows skills
  under a `/zs:` prefix.

→ **[`/update-zskills` lane](#update-zskills-lane)** — the original installer.
  Pick this if you prefer bare slash names (`/run-plan` over `/zs:run-plan`,
  matching the skill prose verbatim), want the skill source mirrored into
  your repo's `.claude/` for reviewable diffs, or are already running this
  lane and don't want to switch.

The lanes are not tiered — neither is deprecated and both produce the same
running behavior. See the [tradeoff matrix](#tradeoff-matrix) for the full
side-by-side.

## Plugin lane

From inside a Claude Code session in your project:

```
/plugin marketplace add zeveck/zskills
/plugin install zs@zskills
```

The first command registers the `zskills` marketplace (the
`.claude-plugin/marketplace.json` manifest in the zskills repo root). The
second installs the `zs` plugin (the full distribution). Restart the
session when prompted so the plugin's hooks load.

To add the block-diagram add-on (3 extra skills for block-diagram
projects), install the `zsbd` plugin from the same marketplace:

```
/plugin install zsbd@zskills
```

On first SessionStart after install, a hook materialises five artifacts
into your repo's `.claude/` that a plugin cannot write at install time:

1. `.claude/agents/verifier.md`
2. `.claude/agents/implementer.md`
3. `.claude/hooks/inject-bash-timeout.sh`
4. `.claude/hooks/verify-response-validate.sh`
5. `.claude/rules/zskills/managed.md` (rendered from `CLAUDE_TEMPLATE.md`)

These five paths are plugin-managed — see [.gitignore guidance](#gitignore-guidance).

## `/update-zskills` lane

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
project settings, installs hooks and scripts into `.claude/`, registers
hooks in `.claude/settings.json`, renders `CLAUDE_TEMPLATE.md` →
`.claude/rules/zskills/managed.md`, and reports any gaps. See the repo
[README](../../README.md) for the full first-run flow (including the
landing-mode prompt). Add the block-diagram add-on with
`/update-zskills install --with-block-diagram-addons`.

## Update workflow

| Lane | Update command | What it does |
|---|---|---|
| Plugin | `/plugin marketplace update` | Re-fetches the marketplace's tracked ref and pulls the new plugin tree. The SessionStart materialiser re-writes the 5 `.claude/` artifacts on next session start (only files still carrying the `zskills-materialised:` sentinel are overwritten — your edits are never clobbered). |
| `/update-zskills` | `/update-zskills install` | Re-fetches the source tree, re-mirrors changed skills/hooks into `.claude/`, and re-renders `managed.md`. Existing config is preserved (no re-prompt). |

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

## Slash-prefix difference

- **Plugin lane** namespaces skills under `/zs:` (and the block-diagram
  add-on under `/zsbd:`): you type `/zs:run-plan`, `/zs:quickfix`, etc.
  The slash menu shows the prefixed names.
- **`/update-zskills` lane** uses bare names: `/run-plan`, `/quickfix`, etc.

The difference is purely the **typed-invocation surface**. Skill-to-skill
dispatch and cron auto-fire are prefix-agnostic — see [Known tradeoffs](#known-tradeoffs) for the one place the prefix leaks into the UX.

## Tradeoff matrix

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

Each release publishes to the prod repo's **`main` branch** and a parallel
**bare `<version>` tag** (e.g. `2026.06.0`). Unpinned consumers track the
moving `main` window; consumers who want reproducibility pin to a specific
version tag.

The default marketplace entry tracks the moving window:

```json
{ "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "ref": "main" } }
```

To **pin to a specific release**, edit your marketplace's `zs` entry to either:

- Override `source.ref` to the bare version tag:

  ```json
  { "name": "zs", "source": { "source": "github", "repo": "zeveck/zskills", "ref": "2026.06.0" } }
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
[RELEASING.md](../../RELEASING.md). The "🚀 Ship to Prod" button
(`ship-to-prod.yml` → `scripts/build-prod.sh`) is the SINGLE publish path: it
strips dev-only artifacts and pushes one complete, plugin-installable tree to
the prod repo's `main` branch plus a bare `<version>` tag. (The legacy
`/update-zskills` lane and the plugin lane both resolve against that same
published tree.)

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

If you've **transiently landed on both** lanes (e.g. mid-switch — not a
supported end-state), follow the `/update-zskills`-lane guidance: the mirror
wins, and the plugin materialiser defers to it (it detects the
`/update-zskills` install lane and exits without writing). Then run
`scripts/switch-install-path.sh` to consolidate to one lane (see
[Switching lanes](#switching-lanes)).

## Marketplace promotion / activation

Activating the public marketplace (so `/plugin marketplace add zeveck/zskills`
resolves) and promoting a release to it are **human-gated publish actions**
performed by maintainers — not part of consumer onboarding. The mechanics live
in [RELEASING.md](../../RELEASING.md):

- The release pushes the prod-stripped, plugin-installable tree to the prod
  repo's `main` branch plus a bare `<version>` tag via the "🚀 Ship to Prod"
  button (`ship-to-prod.yml` → `scripts/build-prod.sh`) — a deliberate,
  human-gated step (the dry-run never pushes).
- The `.claude-plugin/marketplace.json` manifest at the repo root is what
  `/plugin marketplace add zeveck/zskills` reads; its `zs` entry's
  `source.ref` (default `main`) determines which release consumers track.

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
lower-friction choice.

## Switching lanes

Already installed via one lane and want to move to the other? See
[`PLUGIN_MIGRATION.md`](PLUGIN_MIGRATION.md) — `scripts/switch-install-path.sh`
(also reachable as `/update-zskills --switch-install-path={to-plugin|to-update-zskills}`)
is the bidirectional consolidation tool, with Abort/Rollback documented for
both directions.
