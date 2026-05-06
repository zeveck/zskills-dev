---
status: proposal
type: pre-plan
next: /draft-plan
---

# zskills Path Configuration Proposal

Pre-plan brief for relocating zskills' filesystem outputs in consuming repos. Hand to `/draft-plan` once open questions are resolved.

## Problem

zskills currently writes 5 files and 1 directory (`reports/`) directly to a consuming repo's root, plus a `plans/` directory and `.zskills/` runtime state. The root surface — `SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`, `reports/` — is mostly machine-shaped artifacts (forensic logs, regenerated indexes, skill-to-skill plumbing) that surface as repo-root clutter and conflate with the consumer's own root files. The user-curated piece (`plans/`) is mixed in with this machine surface and inherits no flexibility — a consumer who wants plans under `docs/plans/` or hidden entirely has no clean path.

## Current top-level surface (audited)

Files at repo root written by zskills:

- `SPRINT_REPORT.md` — `/fix-issues` (append per sprint), `/fix-report` (mark `[FINALIZED]`), `/run-plan` (update for already-landed)
- `FIX_REPORT.md` — `/fix-report` Step 7
- `PLAN_REPORT.md` — `/run-plan` (regenerated index of `reports/plan-*.md`)
- `VERIFICATION_REPORT.md` — `/verify-changes` (regenerated index of `reports/verify-*.md`)
- `CLAUDE.md.pre-zskills-migration` — `/update-zskills` one-time backup (out of scope here)

Directories at repo root introduced by zskills:

- `reports/` — `/run-plan` (`plan-{slug}.md`), `/verify-changes` (`verify-{scope}.md`), `/add-block` (`new-blocks-{slug}.md`), `/briefing report` (`briefing-{ts}.md`)
- `plans/` — `/draft-plan`, `/refine-plan`, `/plans` (`PLAN_INDEX.md`), `/fix-issues` (`ISSUES_PLAN.md`), `/qe-audit` (`QE_ISSUES.md`), `/add-block` (`BUILD_ISSUES.md`), `/add-example` (`DOC_ISSUES.md`); also mutated in place by `/run-plan`
- `var/` — `dev.pid`, `dev.log` written by consumer's `/update-zskills`-installed `start-dev.sh` stub. Note: `var/` is Unix FHS convention (`/var/log`, `/var/run`) borrowed into a project context where it's an outlier — no major framework (Rails, Django, Cargo, npm, Maven) uses project-level `var/`. The existing zskills convention is flat runtime files under `.zskills/` (`.zskills/dashboard-server.{pid,log}`, `.zskills/monitor-state.json`). This proposal eliminates `var/` and relocates the stub's PID/log files as `.zskills/dev-server.{pid,log}` to match.
- `.zskills/` — runtime state: `tracking/$PIPELINE_ID/{step,phasestep,requires,fulfilled,meta,pipeline,verify-pending-attempts}.*`, `monitor-state.json` (+`.lock`), `work-on-plans-state.json`, `dashboard-server.{pid,log}`, `stub-notes/<stub>.noted`

Files modified at repo root:

- `.gitignore` — `/update-zskills` appends `.zskills/tracking/`, `var/` (the `var/` line goes away with this proposal; superseded by `.zskills/dev-server.*`, covered by the existing `.zskills/` ignore patterns)
- `CLAUDE.md` — left alone by zskills going forward. `/update-zskills` Phase 4 renders `.claude/rules/zskills/managed.md` from `CLAUDE_TEMPLATE.md` (independent of root CLAUDE.md). A one-time legacy cleanup removes pre-Phase-4 zskills-rendered lines from root CLAUDE.md if any are detected, saving a backup at `CLAUDE.md.pre-zskills-migration`. Out of scope here.

Worktree-local files (NOT main repo, listed for completeness): `.zskills-tracked`, `.worktreepurpose`, `.landed`, `.test-results.txt`.

Out of scope for this proposal: `.claude/` install paths (handled by `/update-zskills` install system), `~/.claude/statusline-command.sh`, `.playwright/` (tool, not zskills), `examples/` (block-diagram add-on surface), worktree-local files.

## Design decision

The user-meaningful axis is **curation tier**, not artifact category:

- **Tier 1 — tracked in git, durable project-level state.** Plans (`<NAME>_PLAN.md` — user-authored or `/draft-plan`-generated then user-edited; the only artifact users routinely *open*). Issue trackers (`ISSUES_PLAN.md`, `BUILD_ISSUES.md`, `DOC_ISSUES.md`, `QE_ISSUES.md` — skill-appended; mirror GitHub issues by number; users typically interact via the GitHub issue, not the local file). `PLAN_INDEX.md` (regenerated overview). Common structural property: persists across the project's lifetime, referenced by stable identifiers (plan slug, issue number) from PRs and other Tier 1 files. Common property NOT claimed: that humans frequently open these files directly (only plans hit that bar; trackers and indexes are mostly machine-managed).
- **Tier 2 — forensic exhaust / skill-to-skill plumbing / regenerated indexes.** Per-phase plan reports (`reports/plan-{slug}.md`), verify reports, briefing snapshots, `SPRINT_REPORT.md`/`FIX_REPORT.md` (skill-to-skill state read primarily by `/fix-report`, viewable via the dashboard), `PLAN_REPORT.md`/`VERIFICATION_REPORT.md` indexes. Common property: regenerable, append-only forensic, or skill-internal plumbing; not stably referenced by other artifacts.

Tier 1 gets one config knob. Tier 2 has a fixed location. Reasoning: (a) within each tier, sub-dividing into per-leaf keys is bikeshedding without a real user need; (b) the tracked-vs-gitignored split that motivates flexibility is structural, not configurable — it falls out of the tier boundary; (c) a single knob keeps the consumer's mental model small while solving the actual user complaint (plans visibility).

## Proposed shape

```json
{
  "output": {
    "plans_dir": ".zskills/plans"
  }
}
```

**Default layout (everything zskills under `.zskills/`):**

```
.zskills/
  plans/                          # configurable via plans_dir
    {NAME}_PLAN.md
    PLAN_INDEX.md
    ISSUES_PLAN.md
    BUILD_ISSUES.md
    DOC_ISSUES.md
    QE_ISSUES.md
  audit/                          # fixed location, gitignored, dashboard-viewable
    plan-{slug}.md
    verify-{scope}.md
    briefing-{ts}.md
    new-blocks-{slug}.md
    SPRINT_REPORT.md
    FIX_REPORT.md
    PLAN_REPORT.md
    VERIFICATION_REPORT.md
  tracking/$PIPELINE_ID/...
  monitor-state.json (+ .lock)
  work-on-plans-state.json
  dashboard-server.{pid,log}
  dev-server.{pid,log}            # was top-level var/dev.{pid,log}; flat to match dashboard
  stub-notes/
```

**Surface plans by setting `plans_dir`:**

- `plans_dir: "plans"` — restores current top-level visibility
- `plans_dir: "docs/plans"` — co-locates with project docs
- `plans_dir: "../external-plans/zskills"` — out-of-tree (advanced)

**Top-level zskills footprint after migration:** `.zskills/` only, plus `.gitignore`/`CLAUDE.md` modifications. Six top-level entries removed (`SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`, `reports/`, `var/`).

## Open questions to resolve before /draft-plan

**Q1. Issue trackers — same dir as plans, or separate?**

`ISSUES_PLAN.md`, `BUILD_ISSUES.md`, `DOC_ISSUES.md`, `QE_ISSUES.md` are tracker files: numbered entries (R-/D-/Q-numbered) appended by skills, occasionally read by humans, reviewed in PRs when issues are added or closed.

- (a) **Cohabit with plans under `plans_dir`.** Single key, simplest, matches current cohabitation. Bucket name "plans" loosely covers "user-curated tracked stuff."
- (b) **Separate `issues_dir` key** (default same as `plans_dir`). Independently configurable. Defer until requested.
- (c) **Move to `.zskills/audit/`.** Treat as machine state. Loses PR-review semantics for tracker edits.

Recommendation: (a). No real user pain today, simplest config surface.

**Q2. Default — visible plans or hidden plans?**

- **Hidden default (`plans_dir: ".zskills/plans"`).** Consistent with "everything under `.zskills/`" framing. Clean repo root out of the box. Existing consumers must run `/update-zskills --migrate-paths` on upgrade or set `plans_dir: "plans"` to preserve visibility.
- **Visible default (`plans_dir: "plans"`).** Matches today's behavior. User opts into hiding. Less surprising for existing consumers.

Recommendation: hidden default, leveraging the pre-backcompat posture. The "move most things under `.zskills/`" framing is the whole point; defaulting to visible is a half-step.

## Implementation surface

**Helper: `scripts/zskills-paths.sh`** — sourceable shim, reads `output.plans_dir` from `.claude/zskills-config.json` via established bash-regex JSON-read pattern (no jq, per project convention). Exports:

```
ZSKILLS_PLANS_DIR        # config-resolved, absolute
ZSKILLS_AUDIT_DIR        # $MAIN_ROOT/.zskills/audit
```

Resolves relative to caller-supplied `$MAIN_ROOT` or `$WORKTREE_PATH` — never `pwd`. Critical for `/run-plan` PR mode where the same logical path resolves both in the worktree (where commits land on the feature branch) and on main (where the post-merge state matches).

**Conformance test** — extends `scripts/test-all.sh` with grep across all skills/scripts/hooks for hardcoded literals: `SPRINT_REPORT`, `FIX_REPORT`, `PLAN_REPORT`, `VERIFICATION_REPORT`, `^plans/`, `^reports/`, `"reports/`, `"plans/`. Any match outside doc text or the helper itself fails the suite. Same shape as the existing model-dispatch / no-jq conformance tests.

**Reader/writer surface:**

Writers (must source helper, write to resolved paths):

- `/run-plan` — plans (mutate frontmatter), `audit/plan-{slug}.md`, `audit/PLAN_REPORT.md`, `audit/SPRINT_REPORT.md` (already-landed updates)
- `/fix-issues` — `audit/SPRINT_REPORT.md`, `plans_dir/ISSUES_PLAN.md`
- `/fix-report` — `audit/FIX_REPORT.md`, mutates `audit/SPRINT_REPORT.md`
- `/verify-changes` — `audit/verify-{scope}.md`, `audit/VERIFICATION_REPORT.md`
- `/draft-plan`, `/refine-plan` — `plans_dir/<NAME>_PLAN.md`
- `/plans` — `plans_dir/PLAN_INDEX.md`
- `/qe-audit` — `plans_dir/QE_ISSUES.md`
- `/add-block` — `plans_dir/BUILD_ISSUES.md`, `audit/new-blocks-{slug}.md`
- `/add-example` — `plans_dir/DOC_ISSUES.md`
- `/briefing report` — `audit/briefing-{ts}.md`

Readers (must source helper, read from resolved paths):

- `/briefing` (scans plans_dir + audit, was scanning root + `reports/`)
- `/work-on-plans` (reads `plans_dir/PLAN_INDEX.md`)
- `/fix-report` (reads `audit/SPRINT_REPORT.md`)
- `/run-plan` (reads `plans_dir/<NAME>_PLAN.md`)
- `/refine-plan` (reads `plans_dir/<NAME>_PLAN.md`)
- `briefing.cjs` / `briefing.py` (root `*REPORT*.md` scan must move to audit dir)
- **zskills-dashboard** — first-class consumer; viewer URLs (`/viewer/?file=...`) must resolve through the helper. Already reads `.claude/zskills-config.json` (mutates dashboard block at runtime), so config access is established.

**Gitignore** — `/update-zskills` appends `.zskills/audit/` (and removes `var/` line — superseded by `.zskills/var/` covered by existing `.zskills/` ignore). Existing `.zskills/tracking/` line stays.

## Migration

`/update-zskills --migrate-paths`:

1. Detect existing top-level artifacts (`SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`, `reports/`, `plans/`, `var/`).
2. Move forensic + narrative reports → `.zskills/audit/`.
3. Move `plans/` → `.zskills/plans/` UNLESS user has set `plans_dir: "plans"` (preserves visibility).
4. Move `var/dev.pid` → `.zskills/dev-server.pid`, `var/dev.log` → `.zskills/dev-server.log`. Remove the now-empty `var/` directory. Update the installed `start-dev.sh` and `stop-dev.sh` stubs to reference the new paths (only if they're at the shipped defaults — preserve user customizations).
5. Update `.gitignore`: add `.zskills/audit/`, remove top-level `var/`.
6. Write `.pre-paths-migration` backup marker (mirrors existing `.pre-zskills-migration` pattern for CLAUDE.md).
7. Print one-line summary of moves.

Pre-backcompat posture (per project memory: "zskills is pre-backwards-compat") means no legacy mode flag, no dual-path support. Single migration step, default flip, done.

## Compatibility with existing `.zskills/` usage

Adding `.zskills/plans/`, `.zskills/audit/`, `.zskills/var/` as new subdirectories alongside the existing `tracking/`, `monitor-state.json`, `dashboard-server.{pid,log}`, `work-on-plans-state.json`, `stub-notes/`, `tier1-migration-deferred`, `triggers/` is structurally safe. Verified by independent agent audit (six claims, all VERIFIED) on 2026-04-30:

1. **`clear-tracking.sh` is `tracking/`-scoped only.** `TRACKING_DIR="$MAIN_ROOT/.zskills/tracking"` at line 12; every `find`/`rm` operation rooted at `$TRACKING_DIR` (lines 32, 58, 99, 141, 146, 150, 162). Sibling subdirs are unreachable.

2. **Hook protection is `tracking/`-scoped only.** `hooks/block-unsafe-project.sh.template:201` regex anchors to the literal `\.zskills/tracking`. No broader `.zskills` fence exists. **This is the one caveat**: `rm -rf .zskills/plans` would currently pass the hook. If `.zskills/plans/` will hold user-authored work, the hook regex must be broadened to cover the whole `.zskills/` tree (or per-subdir rules added) as a Phase 1 deliverable, not deferred. Single-line change recommended: replace `\.zskills/tracking` with `\.zskills` to fence the entire tree, since once `.zskills/` holds plans + audit + tracking + runtime state, the whole tree is load-bearing.

3. **Dashboard `collect.py` walks `tracking/` only.** `base = main_root / ".zskills" / "tracking"` at `collect.py:612`; `iterdir()` calls at 621, 627 operate on `base` and direct children only. Specific-file reads elsewhere (`monitor-state.json` at 966, etc.). No `.zskills/*` glob.

4. **No wholesale `.zskills/` wipe.** Every recursive deletion in skills/scripts/hooks targets `.zskills/tracking[/$PIPELINE_ID]/...` specifically. No `find .zskills` outside the tracking-scoped clear script. Only un-scoped `rm` of a `.zskills`-prefixed path is the `.zskills-tracked` sentinel file (not a directory) at `skills/run-plan/SKILL.md:2175`.

5. **`mkdir -p` calls are idempotent and never preceded by a wipe.** Existing pattern e.g. `skills/work-on-plans/SKILL.md:116`. Sibling subdirs already proven viable by `.zskills/triggers/` (`skills/zskills-dashboard/SKILL.md:541`).

6. **All readers use specific subpaths, not `.zskills/*` globs.** Closest to a glob is `zsk.mkdir(exist_ok=True)` at `server.py:248-249` — used for parent creation only, not enumeration.

**Conclusion:** Safe. The one required code change is broadening the hook regex at `block-unsafe-project.sh.template:201` from `.zskills/tracking` to `.zskills` (or per-subdir alternation) so the new value-bearing subdirs get equivalent recursive-delete protection. Folded into Phase 1 of the `/draft-plan` deliverables below.

## Out of scope

- `.claude/` install paths — handled by `/update-zskills` install system; orthogonal.
- `~/.claude/statusline-command.sh` — handled by `/update-zskills`; orthogonal.
- Worktree-local files (`.zskills-tracked`, `.worktreepurpose`, `.landed`, `.test-results.txt`) — already worktree-scoped, no relocation needed.
- `examples/` — block-diagram-app surface, not core zskills.
- `.playwright/` — tool output dir, not zskills-authored.
- Per-leaf path overrides (`narrative_dir`, `audit_dir`, etc.) — explicitly rejected. The tier boundary is the only meaningful split; sub-keys within a tier are bikeshedding.

## What /draft-plan needs to produce

A phase-structured plan covering:

1. **Helper + config schema + hook fence** — `scripts/zskills-paths.sh`, schema entry in `.claude/zskills-config.schema.json`, conformance test, and **broadening of `block-unsafe-project.sh.template:201` recursive-delete regex from `.zskills/tracking` to the whole `.zskills/` tree** (load-bearing since `.zskills/` will now hold user-authored plans).
2. **Writer migration** — every skill listed above, source helper, replace literals. Mirror to `.claude/skills/`.
3. **Reader migration** — every skill listed above, plus `briefing.cjs`/`briefing.py` and dashboard server.
4. **Dashboard viewer** — path-aware URL resolution.
5. **`/update-zskills --migrate-paths`** — one-shot migration with backup marker.
6. **Gitignore update** — through `/update-zskills`.
7. **Self-migration** — apply `--migrate-paths` to zskills repo itself; verify `git ls-files` no longer surfaces top-level reports.
8. **Documentation** — update CLAUDE.md, CHANGELOG, any skill docs that reference the old paths.

Conformance test from Phase 1 gates every subsequent phase. Existing canaries (CANARY1–11) re-run on PR to catch path-resolution regressions in `/run-plan` PR mode and parallel pipelines specifically.
