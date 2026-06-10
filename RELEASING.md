<!-- prod-strip:start -->
# Releasing zskills

This file documents the dev→prod release pipeline. It is stripped from the
public mirror by `scripts/build-prod.sh` — you shouldn't see this on
`github.com/zeveck/zskills`.

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

1. **Bump `plugin.json.version`** in `.claude-plugin/plugin.json` (the `zs`
   plugin). Choose the next `YYYY.MM.N` value (same scheme as the git tag).
   Commit the bump on dev.
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

### Marketplace self-reference, translated on publish

The dev manifest's `zs` `source.repo` SELF-REFERENCES the dev repo
(`zeveck/zskills-dev`), NOT prod. This is deliberate: it lets pre-publish
plugin qual use the GENUINE consumer flow — `/plugin marketplace add
zeveck/zskills-dev` + `/plugin install zs@zskills` — against the dev repo's own
manifest, instead of a hand-rolled local test marketplace. On publish the prod
tree must instead point consumers at prod, so the build path REWRITES it,
exactly analogous to the dev→prod URL rewrite: the shared finalizer
(`scripts/_lib/finalize-prod-tree.sh`) runs `rewrite_marketplace_repo` over the
prod tree's `.claude-plugin/marketplace.json`, swapping `zeveck/zskills-dev` →
`zeveck/zskills` in ONLY the `zs` `source.repo` field (a field-scoped Python
round-trip, NOT a blanket sed; `ref` and `source.source` are untouched). A **residue invariant** immediately
after the rewrite asserts the built manifest carries ZERO `zskills-dev` (bare
substring) and `return 1`s the build if any survives — and because
`build-prod.sh` runs `set -euo pipefail`, that aborts the publish BEFORE any
push. `tests/test-build-rewrite-marketplace-repo.sh` unit-tests the rewrite,
and `tests/test-prod-tree-no-dev-urls.sh` asserts the BUILT tree's manifest is
prod-pointing.

### Cross-lane invariant

For `/plugin marketplace add zeveck/zskills` **without an explicit ref**,
Claude Code reads `marketplace.json` from the prod repo's **default branch,
`main`** — which is exactly where the button publishes. No special default-
branch setting is needed: prod's default branch is `main` (correct), the
button pushes to `main`, and the PUBLISHED `marketplace.json`'s `zs`
`source.ref` is `main` (the publish-time `rewrite_marketplace_repo` changes
ONLY `source.repo`, never `ref`). The pin-by-version idiom is the bare
`<version>` tag the button pushes (e.g. `2026.06.0`, NOT `prod/2026.06.0`).
`tests/test-plugin-ref-consistency.sh` guards this consistency (marketplace ref
↔ workflow push branch ↔ docs pin idiom — and `source.ref` is identical in dev
and prod since only `source.repo` is translated); `tests/test-plugin-d4-hook-siblings.sh`
guards that `build-prod.sh`'s published tree actually contains the D4 hook siblings.

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
2. **Pre-flight write-probe:** pushes a throwaway ref to the prod repo with
   `PROD_PUSH_TOKEN` (via the same explicit auth header the real push uses),
   then deletes it. This genuinely validates **write** access — a plain
   `git ls-remote` read would pass for ANY identity on a public repo (even
   `github-actions[bot]`, which can't write to prod), so it went green while
   the real push later 403'd. The probe pushes its ref at prod's existing
   `main` SHA (no content change) and deletes it again, so the only state
   change is reversible and self-cleaning. Runs on dry-run too, so you can
   catch a dead/under-permissioned token before shipping. Fails the workflow
   in seconds if the token is missing, expired, or read-only — rotate and
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
summary. It publishes no release commit and no tag — the ONE exception is
the pre-flight write-probe, which makes a single reversible push-then-delete
of a throwaway ref to prod (pointing at prod's existing `main` SHA, no
content change) to confirm write access. Nothing else is pushed.

**Mandatory before the next real ship:** any edit to
`.github/workflows/ship-to-prod.yml` MUST be validated by a `Dry run`-checked
workflow run before you ship for real. The prod auth path is secret-gated
(`PROD_PUSH_TOKEN`) and cannot be exercised by ordinary repo CI, so a dry-run
— which still runs the pre-flight write-probe against prod — is the ONLY
pre-ship validation of that path. Skipping it has shipped broken auth twice
(a 403, then a 400 duplicate-header) caught only at ship time.

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

## When the PAT expires

GitHub emails the PAT owner ~7 days before expiry. If you miss the warning
and click Ship to Prod with an expired token, the pre-flight step fails
immediately and the rest of the workflow never runs — nothing is tagged,
nothing is pushed, nothing needs cleanup. Just rotate the PAT (same steps
as the one-time setup above, updating the existing `PROD_PUSH_TOKEN`
secret rather than creating a new one) and click Run again.
<!-- prod-strip:end -->
