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
| `append-backfill-phase.sh`   | 1      | `draft-tests`                |
| `append-tests-section.sh`    | 1      | `draft-tests`                |
| `apply-preset.sh`            | 1      | `update-zskills`             |
| `briefing.cjs`               | 1      | `briefing`                   |
| `briefing.py`                | 1      | `briefing`                   |
| `build-prod.sh`              | 2      | release-only repo tooling; never installed to consumers (called by `.github/workflows/ship-to-prod.yml:80`; documented in `RELEASING.md:5,47,64,71,78,82`) |
| `clear-tracking.sh`          | 1      | `update-zskills`             |
| `compute-cron-fire.sh`       | 1      | `run-plan`                   |
| `convergence-check.sh`       | 1      | `draft-tests`                |
| `coverage-floor-precheck.sh` | 1      | `draft-tests`                |
| `create-worktree.sh`         | 1      | `create-worktree`            |
| `detect-language.sh`         | 1      | `draft-tests`                |
| `draft-orchestrator.sh`      | 1      | `draft-tests`                |
| `flip-frontmatter-status.sh` | 1      | `draft-tests`                |
| `gap-detect.sh`              | 1      | `draft-tests`                |
| `insert-prerequisites.sh`    | 1      | `draft-tests`                |
| `insert-test-spec-revisions.sh` | 1   | `draft-tests`                |
| `land-phase.sh`              | 1      | `commit`                     |
| `mirror-skill.sh`            | 2      | release/repo tooling; called by `tests/test-mirror-skill.sh` and (per Phase 1 Design) by every phase's mirror-discipline step in lieu of `rm -rf .claude/skills/<name> && cp -a ...` |
| `parse-plan.sh`              | 1      | `draft-tests`                |
| `plan-drift-correct.sh`      | 1      | `run-plan`                   |
| `port.sh`                    | 1      | `update-zskills`             |
| `post-run-invariants.sh`     | 1      | `run-plan`                   |
| `re-invocation-detect.sh`    | 1      | `draft-tests`                |
| `review-loop.sh`             | 1      | `draft-tests`                |
| `sanitize-pipeline-id.sh`    | 1      | `create-worktree`            |
| `statusline.sh`              | 1      | `update-zskills` (source moves; install destination still `~/.claude/statusline-command.sh`) |
| `stop-dev.sh`                | 2      | currently functional generic implementation; consumer stack writes PIDs to `var/dev.pid`. **Note:** full conversion to a formal failing stub is deferred to a follow-up plan covering the consumer stub-callout pattern. |
| `test-all.sh`                | 2      | already a partial template (`{{E2E_TEST_CMD}}` placeholders); customized by consumer with their own test commands. **Note:** full conversion to a formal failing stub is deferred to the same follow-up plan. |
| `verify-completed-checksums.sh` | 1   | `draft-tests`                |
| `worktree-add-safe.sh`       | 1      | `create-worktree`            |
| `write-landed.sh`            | 1      | `commit`                     |
| `zskills-stub-lib.sh`        | 1      | `update-zskills`             |

Total: 29 Tier 1 (`append-backfill-phase`, `append-tests-section`,
`apply-preset`, `briefing.cjs`, `briefing.py`, `clear-tracking`,
`compute-cron-fire`, `convergence-check`, `coverage-floor-precheck`,
`create-worktree`, `detect-language`, `draft-orchestrator`,
`flip-frontmatter-status`, `gap-detect`, `insert-prerequisites`,
`insert-test-spec-revisions`, `land-phase`, `parse-plan`,
`plan-drift-correct`, `port`, `post-run-invariants`,
`re-invocation-detect`, `review-loop`, `sanitize-pipeline-id`,
`statusline`, `verify-completed-checksums`, `worktree-add-safe`,
`write-landed`, `zskills-stub-lib`); 4 Tier 2 (`build-prod.sh`,
`mirror-skill.sh`, `stop-dev.sh`, `test-all.sh`).

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
scripts/convergence-check.sh
scripts/coverage-floor-precheck.sh
scripts/create-worktree.sh
scripts/detect-language.sh
scripts/insert-prerequisites.sh
scripts/land-phase.sh
scripts/parse-plan.sh
scripts/plan-drift-correct.sh
scripts/port.sh
scripts/post-run-invariants.sh
scripts/review-loop.sh
scripts/sanitize-pipeline-id.sh
scripts/statusline.sh
scripts/worktree-add-safe.sh
scripts/write-landed.sh
scripts/zskills-stub-lib.sh
```

Phase 4 reads this list (or recomputes it via the parser above) when
deciding which legacy `scripts/<name>` files to delete in a consumer
repo on next `update-zskills` run.

## Failing-stub body revisions

Failing-stub bodies (`post-create-worktree.sh`, `dev-port.sh`,
`start-dev.sh`, `stop-dev.sh`, `test-all.sh`) are version-shipped
artifacts. Future PRs that change a failing-stub body MUST add the OLD
body's hash to
`skills/update-zskills/references/tier1-shipped-hashes.txt` so consumers
running the prior version are not flagged as user-modified by Step D.5
(consumers' `scripts/stop-dev.sh` / `scripts/test-all.sh` would otherwise
mismatch the new shipped hash and emit "WARNING: user-modified" prompts
at every `/update-zskills` run, even though the file is pristine).

This applies to the existing `scripts/stop-dev.sh` and
`scripts/test-all.sh` only after the consumer-stub-callouts plan Phase 5
landed their failing-stub bodies; the three stubs in `stubs/`
(`post-create-worktree.sh`, `dev-port.sh`, `start-dev.sh`) are net-new
in that plan and have no prior shipped body to grandfather.

If `tier1-shipped-hashes.txt` does not yet exist (it's a Step D.5
mechanism from `SCRIPTS_INTO_SKILLS_PLAN.md` Phase 4), and the existing
Step D.5 logic does not currently hash-check `stop-dev.sh` /
`test-all.sh` (verified at `skills/update-zskills/SKILL.md:960-962` —
they are explicitly excluded from STALE_LIST), the policy is
forward-looking: the doc captures the requirement so that if Step D.5 is
ever extended to cover failing-stub bodies, the OLD-hash discipline is
already in place.

The bodies of `stop-dev.sh` and `test-all.sh` (now failing stubs)
are versioned at the source location (`scripts/stop-dev.sh` and
`scripts/test-all.sh`) and updated in place by the maintainers;
consumers do NOT auto-receive body updates because their
`scripts/<stub>.sh` is consumer-owned post-install (Step D
skip-if-exists semantics).
