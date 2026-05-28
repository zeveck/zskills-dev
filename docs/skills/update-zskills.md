# /update-zskills

> Install or update Z Skills supporting infrastructure: CLAUDE.md agent rules, safety hooks, helper scripts, and skill dependencies.

## Usage

```
/update-zskills [install | --rerender | --migrate-paths] [cherry-pick | locked-main-pr | direct]
                [--with-addons | --with-block-diagram-addons]
```

## Arguments

| Argument | Required | Description |
|----------|----------|-------------|
| `install` | No | Force a full first-time setup (skip detection step) |
| `--rerender` | No | Regenerate `.claude/rules/zskills/managed.md` from current config |
| `--migrate-paths` | No | One-shot relocation of legacy artifacts into path-config layout |
| `cherry-pick` | No | Landing mode: cherry-pick changes |
| `locked-main-pr` | No | Landing mode: PR when main is protected |
| `direct` | No | Landing mode: direct to main |
| `--with-addons` | No | Include add-on skills |
| `--with-block-diagram-addons` | No | Include block-diagram add-on skills |

## Modes

### Default (no argument)

Smart detection: if nothing is installed, does a full install. If already installed, pulls latest, updates changed skills, and fills new gaps. Always begins with an audit.

### `install`

Force a full first-time setup, skipping the detection step.

### `--rerender`

Regenerate `.claude/rules/zskills/managed.md` against the current config. Simple full-file rewrite. No audit, no preset, no hooks/scripts touched.

### `--migrate-paths`

One-shot deterministic relocation of legacy artifacts into the path-config layout (`docs/plans/` for plan files, `.zskills/audit/` for reports, `docs/issues/` for issue trackers). Idempotent -- refuses to re-run if the migration manifest already exists.

## Examples

```
/update-zskills
/update-zskills install
/update-zskills --rerender
/update-zskills --migrate-paths
/update-zskills install --with-addons
/update-zskills install --with-block-diagram-addons
/update-zskills install direct
```

## Common Patterns

- **First install:** `/update-zskills install` -- set up Z Skills infrastructure from scratch
- **Update existing:** `/update-zskills` -- pull latest changes and update
- **After config change:** `/update-zskills --rerender` -- regenerate managed rules from config
- **Migrate legacy layout:** `/update-zskills --migrate-paths` -- move artifacts to the standard path-config layout

## Tips & Gotchas

- The default mode audits the current state and reports what was found and what was done
- `--rerender` only touches `.claude/rules/zskills/managed.md` -- it never modifies `./CLAUDE.md`
- `--migrate-paths` writes a `.pre-paths-migration` manifest as a write-once idempotency lock
- Add-on skills (`--with-addons`) provide domain-specific functionality (e.g., block-diagram skills)
