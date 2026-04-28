# Script Ownership Registry

Authoritative ownership table for every script under `scripts/` (Tier-1
machinery that moves into a skill, and Tier-2 release/consumer-tooling
that stays put). This file is parsed by `/run-plan` Phase 4 migration
logic and the drift test in WI 4.8 case 6a — preserve the column layout.

## Tier definitions

- **Tier 1** — zskills internal machinery; source moves into the
  owning skill at `skills/<owner>/scripts/<name>`. Cross-skill callers
  invoke via `"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"`
  (shipped) or `"$REPO_ROOT/skills/<owner>/scripts/<name>"` (zskills
  source-tree tests).
- **Tier 2** — release-only repo tooling consumed by CI, OR
  consumer-customizable utility (template/stub). Stays at `scripts/`.
  Hooks, `CLAUDE_TEMPLATE.md`, and `README.md` config schemas continue
  to name `scripts/<x>.sh`.

## Ownership table

| Script                       | Tier   | Owner / disposition          |
|------------------------------|--------|------------------------------|
| `apply-preset.sh`            | 1      | `update-zskills`             |
| `briefing.cjs`               | 1      | `briefing`                   |
| `briefing.py`                | 1      | `briefing`                   |
| `build-prod.sh`              | 2      | release-only repo tooling; never installed to consumers (called by `.github/workflows/ship-to-prod.yml:80`; documented in `RELEASING.md:5,47,64,71,78,82`) |
| `clear-tracking.sh`          | 1      | `update-zskills`             |
| `compute-cron-fire.sh`       | 1      | `run-plan`                   |
| `create-worktree.sh`         | 1      | `create-worktree`            |
| `land-phase.sh`              | 1      | `commit`                     |
| `mirror-skill.sh`            | 2      | release/repo tooling; called by `tests/test-mirror-skill.sh` and (per Phase 1 Design) by every phase's mirror-discipline step in lieu of `rm -rf .claude/skills/<name> && cp -a ...` |
| `plan-drift-correct.sh`      | 1      | `run-plan`                   |
| `port.sh`                    | 1      | `update-zskills`             |
| `post-run-invariants.sh`     | 1      | `run-plan`                   |
| `sanitize-pipeline-id.sh`    | 1      | `create-worktree`            |
| `statusline.sh`              | 1      | `update-zskills` (source moves; install destination still `~/.claude/statusline-command.sh`) |
| `stop-dev.sh`                | 2      | currently functional generic implementation; consumer stack writes PIDs to `var/dev.pid`. **Note:** full conversion to a formal failing stub is deferred to a follow-up plan covering the consumer stub-callout pattern. |
| `test-all.sh`                | 2      | already a partial template (`{{E2E_TEST_CMD}}` placeholders); customized by consumer with their own test commands. **Note:** full conversion to a formal failing stub is deferred to the same follow-up plan. |
| `worktree-add-safe.sh`       | 1      | `create-worktree`            |
| `write-landed.sh`            | 1      | `commit`                     |

Total: 14 Tier 1 (`apply-preset`, `briefing.cjs`, `briefing.py`,
`clear-tracking`, `compute-cron-fire`, `create-worktree`, `land-phase`,
`plan-drift-correct`, `port`, `post-run-invariants`,
`sanitize-pipeline-id`, `statusline`, `worktree-add-safe`,
`write-landed`); 4 Tier 2 (`build-prod.sh`, `mirror-skill.sh`,
`stop-dev.sh`, `test-all.sh`).

## Format contract

Future agents adding rows MUST preserve this exact layout — it is parsed
by `awk -F'|'` in multiple places (Phase 4 WI 4.2 hash-file generator,
WI 4.8 case 6a drift test, Phase 5 WI 5.1, Phase 3b WI 3b.1):

- **Column 1** — `` `script-name.ext` `` (backtick-quoted, surrounded by
  whitespace).
- **Column 2** — ` 1 ` or ` 2 ` (literal digit, with surrounding
  whitespace; no other content).
- **Column 3** — owner-or-disposition prose. Tier-1 rows name a single
  owning skill (in backticks). Tier-2 rows describe disposition.

Adding a row in any other format breaks the parsers and the canonical
Tier-1 enumeration below.

## Cross-skill path convention

- **Source-tree zskills tests** invoke scripts via the absolute
  `"$REPO_ROOT/skills/<owner>/scripts/<name>"` form. The bare-relative
  `skills/<owner>/scripts/<name>` form is FORBIDDEN. `tests/run-all.sh`
  exports `CLAUDE_PROJECT_DIR="$REPO_ROOT"` (Phase 5 WI 5.7) so
  cross-skill invocations also resolve under tests.
- **Shipped (consumer-side) and cross-skill callers** MUST use the
  bare-`$CLAUDE_PROJECT_DIR` form
  `"$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>"`.
  The harness sets `CLAUDE_PROJECT_DIR` in spawned bash blocks; if it
  is unset at a callsite, fail loud rather than silently expand to an
  invalid path.
- **Same-skill internal callers** (e.g., `create-worktree.sh` invoking
  `worktree-add-safe.sh` in its own skill) compute a path from the
  script's own location:
  `SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)`. Symlink invocation is
  not supported in this form (use `readlink -f` resolution if needed).

## Canonical Tier-1 name parser (DA-5 single source of truth)

Every grep sweep across this plan that enumerates Tier-1 names MUST
drive off this file:

```bash
TIER1_NAMES=$(awk -F'|' '$3 ~ /^[[:space:]]*1[[:space:]]*$/ {
  gsub(/[[:space:]`]/, "", $2); print $2
}' skills/update-zskills/references/script-ownership.md)
```

Phases 3b, 5, and 6 keep illustrative closed lists for human readability
in their grep recipes, but their acceptance criteria reference the
parser-driven form so a future row addition does not drift the sweep.

## STALE_LIST

The STALE_LIST is the set of `scripts/<name>` paths that Phase 4's
`/update-zskills` migration logic detects in a consumer's checkout and
removes after confirming the new skill-mirrored copies exist. It is the
Tier-1 name set with a `scripts/` prefix:

```
scripts/apply-preset.sh
scripts/briefing.cjs
scripts/briefing.py
scripts/clear-tracking.sh
scripts/compute-cron-fire.sh
scripts/create-worktree.sh
scripts/land-phase.sh
scripts/plan-drift-correct.sh
scripts/port.sh
scripts/post-run-invariants.sh
scripts/sanitize-pipeline-id.sh
scripts/statusline.sh
scripts/worktree-add-safe.sh
scripts/write-landed.sh
```

Phase 4 reads this list (or recomputes it via the parser above) when
deciding which legacy `scripts/<name>` files to delete in a consumer
repo on next `update-zskills` run.
