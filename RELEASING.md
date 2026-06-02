<!-- prod-strip:start -->
# Releasing zskills

This file documents the dev→prod release pipeline. It is stripped from the
public mirror by `scripts/build-prod.sh` — you shouldn't see this on
`github.com/zeveck/zskills`.

### Migration: ZSKILLS_PATH_CONFIG (post-2026-05-08)

See CHANGELOG entry for `feat(paths)` and
`.claude/skills/update-zskills/references/path-config-upgrade.md` for
the long-tail customization upgrade prompt.

## Dogfooding lanes (plugin + legacy)

zskills is distributed via TWO permanent, first-class install lanes, and we
dogfood BOTH from this repo:

- **Plugin lane** — load the in-repo plugin in-place with
  `claude --plugin-dir .`. Claude Code reads `.claude-plugin/plugin.json`
  (the `zs` plugin) and `block-diagram/.claude-plugin/plugin.json` (the
  `zsbd` addon), registers the hooks in `hooks/hooks.json`, and resolves
  skill paths under `${CLAUDE_PLUGIN_ROOT}`. Iterate with
  `edit → /reload-plugins → test`. No rendering/mirroring step is needed —
  the plugin runs from source. Validate manifests with
  `claude plugin validate . --strict` (marketplace) and
  `claude plugin validate ./block-diagram --strict` (zsbd plugin).
- **Legacy `/update-zskills` lane** — the bespoke installer that mirrors
  `skills/` → `.claude/skills/`, copies `hooks/*.sh` → `.claude/hooks/`,
  registers hooks in `.claude/settings.json`, and renders
  `CLAUDE_TEMPLATE.md` → `.claude/rules/zskills/managed.md`. Dogfood it by
  running `/update-zskills install` against the source tree; iterate with
  `edit → /update-zskills --rerender → test`.

### Repeatable plugin-install dogfood (`scripts/dogfood-plugin-install.sh`)

`claude --plugin-dir .` loads the plugin from the dev working tree, but it
does NOT exercise the real `claude plugin install` path (marketplace
resolution → clone → cache). To dogfood THAT half on demand without pushing
to prod and without leaving cruft in `~/.claude`, run:

```bash
bash scripts/dogfood-plugin-install.sh            # install from public dev @ main
bash scripts/dogfood-plugin-install.sh --ref my-branch   # from a pushed branch
bash scripts/dogfood-plugin-install.sh --keep     # keep the /tmp dir to inspect
```

It runs the whole flow under an isolated `HOME` (= `CLAUDE_CONFIG_DIR`) in
`/tmp`, recursively removed on exit (zero cruft): it (1) builds the
prod-stripped tree via `build-plugin-release.sh` inside a throwaway clone
with a clone-scoped git identity (the `git commit-tree` step needs an ident a
fresh clone lacks), (2) writes a throwaway `marketplace.json` whose single
`zs` entry uses an https `url` source pointing at
`https://github.com/zeveck/zskills-dev.git` at `--ref` (the `url` source —
NOT the prod `github` shorthand, which clones via git@ SSH and fails in a
keyless sandbox), (3) `claude plugin marketplace add` + `claude plugin
install zs@zskills`, then (4) asserts the cached tree under the isolated
config root contains `plugin.json`, `hooks/hooks.json`, the non-empty
`skills/` dir, `hooks/session-start-materialise.sh`, and the lane-portable
`zskills-resolve-config.sh`. Because the install pulls from the PUBLIC dev
repo at `--ref`, the branch must already be pushed there to reflect non-main
work. If the `claude` CLI is absent (e.g. a bare CI runner) it SKIPs and
exits 0.

**What the install dogfood PROVES vs does NOT.** It validates the
clone + marketplace-resolution + cache layer only — "installed" is
necessary, not sufficient. It does NOT exercise RUNTIME resolution: skills
resolving under `${CLAUDE_PLUGIN_ROOT}`, hooks actually firing, `/zs:` slash
dispatch, or the SessionStart materialiser writing the 5 consumer artifacts.
Confirming those needs a real AUTHED `claude` session (interactive or
headless `claude -p` — both require login); neither the install dogfood nor
any non-interactive run covers them.

**The complementary BEHAVIOR test — `claude --plugin-dir <built-tree>`.**
The other half of dogfooding is plugin RUNTIME behavior, via the documented
official local-dev path: `claude --plugin-dir <tree>` sets
`CLAUDE_PLUGIN_ROOT`, registers the `hooks/hooks.json` hooks, and namespaces
the skills under `/zs:`. Get a built tree by running
`bash scripts/build-plugin-release.sh` and checking out the resulting
`prod/main` ref into a directory (`git worktree add <dir> prod/main`). **Run
`--plugin-dir` from a CLEAN, mirror-less consumer dir — NEVER from inside
this dev repo.** zskills-dev carries a `.claude/skills/` mirror (the
dogfooding exception, case 3 in CLAUDE.md's plugin-lane mental model), so
running `--plugin-dir .` here reproduces the "dogfood-mask": the mirror
satisfies skill lookups and masks whether the plugin lane actually resolves
under `${CLAUDE_PLUGIN_ROOT}`. Only a mirror-less consumer dir validates
mirror-less resolution — the norm a real plugin consumer lands in. Full
runtime confirmation (hooks firing, `/zs:` dispatch, the materialiser
writing its 5 artifacts) still requires a logged-in session.

Both lanes are exercised by CI (the plugin-lane CI job lands in Phase 5).
Neither lane is retired; both are supported indefinitely. See
`docs/plans/PLUGIN_DISTRIBUTION.md` for the full dual-path design.

The D16(a) conditional-skip shim
(`hooks/_lib/plugin-hook-skip-if-mirrored.sh`) makes it safe to have BOTH
lanes installed at once in a consumer repo: each plugin-registered hook
defers to a settings.json-registered copy of the same hook (basename match,
with a `# zskills-hook-version:` skew guard) so hooks never double-fire.

## Release flow — ONE publish serves BOTH lanes

There is a SINGLE publish path: the **🚀 Ship to Prod** button
(`.github/workflows/ship-to-prod.yml` → `scripts/build-prod.sh`). It strips
dev-only artifacts from the current dev HEAD and pushes ONE complete,
plugin-installable tree to the prod repo's **`main` branch** plus a bare
**`YYYY.MM.N` tag**. That single published tree serves BOTH the legacy
`/update-zskills` lane (which mirrors `skills/` + hooks) AND the plugin lane
(`build-prod.sh` keeps the plugin manifests AND generates the D4 suffixless
hook siblings, so `/plugin install zs@zskills` gets a complete plugin).

`scripts/build-plugin-release.sh` is **NOT the publish path** — it is a local
dogfood / prod-tree builder (and the source of the D4/strip test fixtures). It
shares the plugin-completion logic with `build-prod.sh` via
`scripts/_lib/finalize-prod-tree.sh`, so the two builders cannot diverge.

Release steps:

1. **Bump BOTH `plugin.json.version` files in lockstep** (D10):
   `.claude-plugin/plugin.json` (the `zs` plugin) and
   `block-diagram/.claude-plugin/plugin.json` (the `zsbd` addon). They MUST
   stay equal — `tests/test-plugin-marketplace.sh` asserts
   `zs.version == zsbd.version`. Choose the next `YYYY.MM.N` value (same
   scheme as the git tag). Commit the bump on dev.
2. **(Optional) Dry-build / inspect locally.** Two ways:
   - **Workflow dry-run:** click Run workflow with **Dry run** checked — it
     builds the prod tree and shows the file diff in the run summary, pushing
     nothing.
   - **Local builder:** `bash scripts/build-plugin-release.sh` (no `--push`)
     materialises a LOCAL `prod/main` + `prod/<version>` staging ref you can
     inspect with `git ls-tree -r refs/heads/prod/main`. Verify the strip set
     returns 0 hits:
     `git ls-tree -r refs/heads/prod/main | grep -E 'CANARY|RELEASING|DEV-QUAL|dev_only|build-.*\.sh|MW-EXAMPLE'`.
     Clean up after (`git update-ref -d refs/heads/prod/main` +
     `git update-ref -d refs/tags/prod/<version>`). NOTE: those `prod/...`
     ref names are this builder's LOCAL staging namespace; on `--push` it
     pushes them to prod's BARE `main` + bare `<version>` — exactly what the
     button publishes.
3. **Publish via the button.** Click **🚀 Ship to Prod** (Dry run unchecked).
   The workflow gates on the full test suite, computes the next `YYYY.MM.N`
   tag, runs `build-prod.sh`, and pushes the stripped tree to prod's `main`
   branch + the bare tag (prod-first, so dev stays clean on any failure).
4. **Notify consumers.** Plugin-lane consumers refresh via
   `/plugin marketplace update` (or auto-update if enabled); legacy-lane
   consumers run `/update-zskills install` (smart-detect pulls the new
   skills/hooks and re-renders `managed.md`). The CHANGELOG entry is the
   per-line summary for both.

### Cross-lane invariant

For `/plugin marketplace add zeveck/zskills` **without an explicit ref**,
Claude Code reads `marketplace.json` from the prod repo's **default branch,
`main`** — which is exactly where the button publishes. No special default-
branch setting is needed: prod's default branch is `main` (correct), the
button pushes to `main`, and `marketplace.json`'s `zs` `source.ref` is `main`.
The pin-by-version idiom is the bare `<version>` tag the button pushes (e.g.
`2026.06.0`, NOT `prod/2026.06.0`). `tests/test-plugin-ref-consistency.sh`
guards this consistency (marketplace ref ↔ workflow push branch ↔ docs pin
idiom); `tests/test-plugin-d4-hook-siblings.sh` guards that `build-prod.sh`'s
published tree actually contains the D4 hook siblings.

## TL;DR

1. Click **🚀 Ship to Prod** in the README (or go to Actions → "🚀 Ship to Prod" → Run workflow).
2. Leave "Dry run" unchecked. Click **Run workflow**.
3. ~1–2 min later, `github.com/zeveck/zskills` has the new release plus a matching tag on both repos.

## One-time setup

The workflow pushes to `github.com/zeveck/zskills` using a personal access
token stored as a secret in this repo.

1. **Create a fine-grained PAT** at <https://github.com/settings/personal-access-tokens/new>:
   - **Resource owner**: your account (same one that owns both repos).
   - **Repository access**: Only select repositories → `zeveck/zskills`.
   - **Permissions → Repository permissions**:
     - **Contents**: Read and write
     - **Metadata**: Read (auto)
   - Expiration: whatever you want (90 days default is fine; rotate when it expires).
2. **Add it as a repo secret** in this (dev) repo. Two ways, pick one:
   - **CLI (preferred):** `gh secret set PROD_PUSH_TOKEN --repo zeveck/zskills-dev` — paste the PAT at the prompt. Requires `gh auth status` to show you're signed in with admin on `zskills-dev`.
   - **Web UI (fallback):** Settings → Secrets and variables → Actions → New repository secret. Name: `PROD_PUSH_TOKEN`. Value: paste the PAT.
3. Done. The workflow will pick it up automatically.

The default `GITHUB_TOKEN` (scoped to this repo) handles tagging dev and
creating the release — no extra setup needed for that side.

## What the workflow does

On dispatch, it:

1. Checks out the current dev HEAD (full history, so it can enumerate tags).
2. **Pre-flight:** `git ls-remote`s the prod repo with `PROD_PUSH_TOKEN`
   to validate the PAT. Fails the workflow in seconds if the token is
   missing or expired — **zero state change required**, just rotate and
   re-run.
3. Runs `bash tests/run-all.sh` as a gate. Any red test aborts.
4. Computes the next tag as `YYYY.MM.N` where `N` is the count of existing
   tags matching `YYYY.MM.*` (zero-indexed — first release of a month is
   `.0`, second is `.1`, etc.).
5. Runs `scripts/build-prod.sh` to strip dev-only artifacts from the working
   tree (see that file's header for the full list of transforms).
6. Writes the stripped tree as a new commit whose parent is prod's current
   `main` (fetched as the `prod/main` remote-tracking ref), so prod ends up
   with a linear history of release snapshots.
7. **Prod-first push:** pushes the stripped commit to prod's BARE `main`
   branch (`refs/heads/main`), then the matching bare `<version>` tag
   (`refs/tags/${TAG}`) to prod. Only **after** prod succeeds does dev get
   tagged and a GitHub Release created. Any failure before this point leaves
   dev untouched — no orphan tags, no partial state.

## Who can release

Only collaborators with Write access to this (dev) repo. The repo is public,
so anyone can *see* the Actions tab, but random visitors cannot trigger the
workflow.

## Dry run

If you changed `scripts/build-prod.sh` and want to verify the transforms
without actually shipping: click Run workflow, check **Dry run**, run. The
workflow will build the prod tree and show the file diff in the run
summary, but will not push anything or tag anything.

## Adding new transforms

Extend `scripts/build-prod.sh`. Common candidates:

- Strip additional dev-only dirs (`plans/`, `reports/`, `tests/`, etc. — none
  currently stripped, since they're small and useful for readers of the prod
  source. Revisit if they grow.)
- Rewrite dev-only links in other markdown files by adding
  `<!-- prod-strip:start --> … <!-- prod-strip:end -->` around them and
  calling `strip_markers <file>` in build-prod.sh.
- Mark a skill as dev-only by adding `dev_only: true` to its SKILL.md
  front-matter — no script change needed, already honored.

Run the workflow in dry-run mode after any build-prod.sh change.

## Recovering from a bad release

Because prod's `main` is always built on top of the previous prod `main`
commit (not force-pushed), a bad release leaves a bad commit at HEAD. To
recover:

- Simplest: ship a new release with the fix. Prod's `main` advances forward.
- If the bad release must be expunged entirely, you'll need to force-push
  prod's `main` manually (locally, authenticated as a prod collaborator) and
  delete the bad tag from both repos. The workflow intentionally does not
  automate this — expunging history should be rare and deliberate.

### Migration: SCRIPTS_INTO_SKILLS_PLAN (post-2026.04)

Upgrading from a pre-2026.04 release to this release:

- **`scripts/` is now slimmer.** Skill-machinery scripts moved
  into their owning skills (`.claude/skills/<owner>/scripts/<name>`).
  `/update-zskills` detects leftover copies in your repo's
  `scripts/` and offers to remove them after verifying they
  match a known release. User-modified scripts are kept and
  flagged with a defer-marker mechanism.
- **`dev_server.port_script` removed** from the config schema.
  `port.sh` lives at one canonical location inside the
  `update-zskills` skill; consumers no longer override its
  location via config. A future plan may reintroduce a
  consumer-overridable callout under a different field name.
- **`dev_server.default_port` added** (integer, default 8080).
  Consumers may set this to override the main-repo dev port.
  `/update-zskills` writes it on greenfield install and
  backfills it into existing configs.
- **New file `.zskills/tier1-migration-deferred`** —
  consumer-side per-file marker that suppresses the
  user-modified warning for specific files on subsequent
  `/update-zskills` runs. Append filenames one per line.
- **New file `.claude/skills/update-zskills/references/tier1-shipped-hashes.txt`**
  — release-side artifact shipped via the skill mirror; used
  by the migration logic to verify whether a leftover script
  is an exact upstream copy.
- **Hook help-text path updated** for `clear-tracking.sh`:
  `block-unsafe-project.sh` now points at the skill-mirror
  location. If you've aliased the old `bash scripts/clear-tracking.sh`
  invocation, update to `bash .claude/skills/update-zskills/scripts/clear-tracking.sh`.
- **`statusline.sh` source moved** but install destination
  (`~/.claude/statusline-command.sh`) unchanged — invocation
  path is identical post-install. Only relevant if you've
  manually edited `scripts/statusline.sh` in your repo;
  port the change to
  `.claude/skills/update-zskills/scripts/statusline.sh`.

The CHANGELOG entries (the `refactor(scripts):` and
`feat(config):` lines under the corresponding release) remain
the per-line summary; this section is the longer-form
companion. See `plans/SCRIPTS_INTO_SKILLS_PLAN.md` for the
full specification.

## When the PAT expires

GitHub emails the PAT owner ~7 days before expiry. If you miss the warning
and click Ship to Prod with an expired token, the pre-flight step fails
immediately and the rest of the workflow never runs — nothing is tagged,
nothing is pushed, nothing needs cleanup. Just rotate the PAT (same steps
as the one-time setup above, updating the existing `PROD_PUSH_TOKEN`
secret rather than creating a new one) and click Run again.
<!-- prod-strip:end -->
