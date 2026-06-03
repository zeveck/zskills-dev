# /update-zskills

> Install or update the Z Skills supporting infrastructure: the CLAUDE.md agent rules, safety hooks, helper scripts, and skill dependencies the other skills rely on.

## What it does

`/update-zskills` sets up and maintains the shared infrastructure that every other Z Skill depends on. That infrastructure is: the agent rules file (`.claude/rules/zskills/managed.md`, which Claude Code loads automatically each session), the safety hooks under `.claude/hooks/`, the helper scripts under `scripts/`, and the skill files themselves. Running it is how you bring a project from "no Z Skills" to "fully set up," and how you keep an already-set-up project current.

Run with no arguments, it figures out which case you're in. If nothing is installed yet, it does a full first-time install. If Z Skills are already present, it pulls the latest versions, updates any skills that changed, and fills in anything new that's missing. Either way it starts by auditing what's currently on disk and prints a report of what it found before changing anything — so you always see the gap analysis first. The audit itself never modifies files.

On a first install it asks one question: how you want changes to land — directly to `main`, via cherry-pick from a worktree, or as pull requests on a protected `main`. Your answer is saved to `.claude/zskills-config.json` and drives the landing behavior of the execution skills from then on. On later runs it respects the config that's already there and does not re-ask.

After it finishes, it reports what it installed or updated and a one-line version summary comparing your installed version against the latest available, including how many skills changed. The config file and the installed skills are the artifacts; there's no separate report file to read.

## Usage

```
/update-zskills [install | --rerender | --migrate-paths | --switch-install-path={to-plugin|to-update-zskills}]
                [cherry-pick | locked-main-pr | direct]
                [--with-addons | --with-block-diagram-addons]
```

## Typical usage

```
/update-zskills install
/update-zskills
/update-zskills --rerender
/update-zskills locked-main-pr
```

The two everyday forms are `/update-zskills install` to set a project up from scratch, and a bare `/update-zskills` to pull the latest and refresh an existing install. After you hand-edit `.claude/zskills-config.json`, run `/update-zskills --rerender` to regenerate the rules file from the new config. To change only how changes land — without pulling or updating anything — pass a bare landing keyword like `/update-zskills locked-main-pr`.

## Companion skills

`/update-zskills` is the setup skill that configures and is referenced by nearly every other skill; it has no "before" step, but it underpins the rest of the catalog.

- **`/commit`**, **`/do`**, **`/quickfix`**, **`/fix-issues`**, **`/run-plan`** — the execution skills whose landing behavior is governed by the `execution.landing` and `execution.main_protected` config fields that `/update-zskills` writes.
- **`/create-worktree`** — the shared worktree-setup helper installed and kept current as part of the infrastructure these skills call.
- **`/briefing`**, **`/plans`**, **`/zskills-dashboard`** — status and catalog skills that depend on the Python helpers and config `/update-zskills` puts in place.
- **`/verify-changes`** — the change-soundness gate that, like the others, relies on the rules and test config this skill installs.

## Arguments

These can be combined: a mode token, a landing keyword, and an add-on flag are independent and may appear together (for example, `/update-zskills install locked-main-pr --with-addons`).

| Argument | Required | Description |
|----------|----------|-------------|
| `install` | No | Force a full first-time setup, skipping the detect-what's-installed step |
| `--rerender` | No | Regenerate `.claude/rules/zskills/managed.md` from the current config only — no audit, no pull, no hook or script changes; never touches your root `./CLAUDE.md` |
| `--migrate-paths` | No | One-time move of legacy artifacts into the standard layout (plan files under `docs/plans/`, issue trackers under `docs/issues/`, reports under `.zskills/audit/`); runs once and refuses to repeat |
| `--switch-install-path={to-plugin\|to-update-zskills}` | No | Move a project between the two ways of consuming Z Skills, preserving its config and trackers; runs once per direction and is a no-op if already there |
| `cherry-pick` | No | Set landing to cherry-pick from a worktree onto an unprotected `main` |
| `locked-main-pr` | No | Set landing to pull requests on a protected `main` |
| `direct` | No | Set landing to direct commits on an unprotected `main` |
| `--with-addons` | No | Also install/update the available add-on skill packs, not just the core skills |
| `--with-block-diagram-addons` | No | Like `--with-addons`, but limited to the block-diagram add-on pack |

The three landing keywords (`cherry-pick`, `locked-main-pr`, `direct`) are mutually exclusive — pass at most one. A bare landing keyword on its own (no `install`) only rewrites the two landing-related config fields and leaves everything else, including the rest of your config, untouched; it does not pull or update skills. Paired with `install`, it sets the landing mode as part of the full install.

By default only the core skills are installed or updated. Add `--with-addons` (or the narrower `--with-block-diagram-addons`) to also bring in the add-on packs — these are extra, domain-specific skills layered on top of the core set.

## Examples

```
/update-zskills
/update-zskills install
/update-zskills --rerender
/update-zskills --migrate-paths
/update-zskills install --with-addons
/update-zskills install direct
/update-zskills locked-main-pr
```

## Common Patterns

- **First install:** `/update-zskills install` — set up the infrastructure from scratch
- **Update existing:** `/update-zskills` — pull the latest and refresh what's installed
- **After editing config:** `/update-zskills --rerender` — regenerate the rules file from the new config
- **Switch landing mode only:** `/update-zskills locked-main-pr` — change how changes land without pulling anything
- **Move legacy layout:** `/update-zskills --migrate-paths` — relocate plans, issues, and reports into the standard layout

## Tips & Gotchas

- Every run begins with an audit and prints what it found before making any change — read the gap report first.
- `--rerender` only rewrites `.claude/rules/zskills/managed.md`; it never modifies your root `./CLAUDE.md`.
- A bare landing keyword (`/update-zskills cherry-pick`) is a pure landing-mode switch — it changes only the two landing fields and does not pull or update skills.
- `--migrate-paths` runs once. It refuses to repeat after it has migrated, so re-running it is safe and does nothing.
- On a first install you'll be asked once how changes should land; on later runs it respects the config already on disk and won't re-ask.
