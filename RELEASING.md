<!-- prod-strip:start -->
# Releasing zskills

This file documents the dev→prod release pipeline. It is stripped from the
public mirror by `scripts/build-prod.sh` — you shouldn't see this on
`github.com/zeveck/zskills`.

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
6. Writes the stripped tree as a new commit with `prod/main` as its parent,
   so prod ends up with a linear history of release snapshots.
7. **Prod-first push:** pushes the stripped commit to `prod/main`, then the
   matching tag to prod. Only **after** prod succeeds does dev get tagged
   and a GitHub Release created. Any failure before this point leaves dev
   untouched — no orphan tags, no partial state.

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

Because prod's main is always built on top of the previous prod/main (not
force-pushed), a bad release leaves a bad commit at HEAD. To recover:

- Simplest: ship a new release with the fix. Prod's main advances forward.
- If the bad release must be expunged entirely, you'll need to force-push
  prod/main manually (locally, authenticated as a prod collaborator) and
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
