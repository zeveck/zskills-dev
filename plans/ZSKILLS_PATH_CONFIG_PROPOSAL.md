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
- `var/` — `dev.pid`, `dev.log` written by consumer's `/update-zskills`-installed `start-dev.sh` stub
- `.zskills/` — runtime state: `tracking/$PIPELINE_ID/{step,phasestep,requires,fulfilled,meta,pipeline,verify-pending-attempts}.*`, `monitor-state.json` (+`.lock`), `work-on-plans-state.json`, `dashboard-server.{pid,log}`, `stub-notes/<stub>.noted`

Files modified at repo root:

- `.gitignore` — `/update-zskills` appends `.zskills/tracking/`, `var/`
- `CLAUDE.md` — `/init` writes; `/update-zskills` Phase 4 migrates content into `.claude/rules/zskills/managed.md`

Worktree-local files (NOT main repo, listed for completeness): `.zskills-tracked`, `.worktreepurpose`, `.landed`, `.test-results.txt`.

Out of scope for this proposal: `.claude/` install paths (handled by `/update-zskills` install system), `~/.claude/statusline-command.sh`, `.playwright/` (tool, not zskills), `examples/` (block-diagram add-on surface), worktree-local files.

## Design decision

The user-meaningful axis is **curation tier**, not artifact category:

- **Tier 1 — user-curated, tracked, PR-visible.** Plans (`<NAME>_PLAN.md`), issue trackers (`ISSUES_PLAN.md`, `BUILD_ISSUES.md`, `DOC_ISSUES.md`, `QE_ISSUES.md`), `PLAN_INDEX.md`. These are artifacts users author, edit, and review.
- **Tier 2 — machine forensic / skill-to-skill / regenerated indexes.** Per-phase plan reports, verify reports, briefing snapshots, `SPRINT_REPORT.md`/`FIX_REPORT.md` (read primarily by `/fix-report`, surfaced to humans through the dashboard viewer), `PLAN_REPORT.md`/`VERIFICATION_REPORT.md` indexes.

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
  var/                            # promoted from top-level var/
  monitor-state.json (+ .lock)
  work-on-plans-state.json
  dashboard-server.{pid,log}
  stub-notes/
```

**Surface plans by setting `plans_dir`:**

- `plans_dir: "plans"` — restores current top-level visibility
- `plans_dir: "docs/plans"` — co-locates with project docs
- `plans_dir: "../external-plans/zskills"` — out-of-tree (advanced)

**Top-level zskills footprint after migration:** `.zskills/` only, plus `.gitignore`/`CLAUDE.md` modifications. Five top-level entries removed (`SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`, `reports/`).

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
4. Move `var/` → `.zskills/var/`.
5. Update `.gitignore`: add `.zskills/audit/`, remove top-level `var/`.
6. Write `.pre-paths-migration` backup marker (mirrors existing `.pre-zskills-migration` pattern for CLAUDE.md).
7. Print one-line summary of moves.

Pre-backcompat posture (per project memory: "zskills is pre-backwards-compat") means no legacy mode flag, no dual-path support. Single migration step, default flip, done.

## Out of scope

- `.claude/` install paths — handled by `/update-zskills` install system; orthogonal.
- `~/.claude/statusline-command.sh` — handled by `/update-zskills`; orthogonal.
- Worktree-local files (`.zskills-tracked`, `.worktreepurpose`, `.landed`, `.test-results.txt`) — already worktree-scoped, no relocation needed.
- `examples/` — block-diagram-app surface, not core zskills.
- `.playwright/` — tool output dir, not zskills-authored.
- Per-leaf path overrides (`narrative_dir`, `audit_dir`, etc.) — explicitly rejected. The tier boundary is the only meaningful split; sub-keys within a tier are bikeshedding.

## What /draft-plan needs to produce

A phase-structured plan covering:

1. **Helper + config schema** — `scripts/zskills-paths.sh`, schema entry in `.claude/zskills-config.schema.json`, conformance test.
2. **Writer migration** — every skill listed above, source helper, replace literals. Mirror to `.claude/skills/`.
3. **Reader migration** — every skill listed above, plus `briefing.cjs`/`briefing.py` and dashboard server.
4. **Dashboard viewer** — path-aware URL resolution.
5. **`/update-zskills --migrate-paths`** — one-shot migration with backup marker.
6. **Gitignore update** — through `/update-zskills`.
7. **Self-migration** — apply `--migrate-paths` to zskills repo itself; verify `git ls-files` no longer surfaces top-level reports.
8. **Documentation** — update CLAUDE.md, CHANGELOG, any skill docs that reference the old paths.

Conformance test from Phase 1 gates every subsequent phase. Existing canaries (CANARY1–11) re-run on PR to catch path-resolution regressions in `/run-plan` PR mode and parallel pipelines specifically.
