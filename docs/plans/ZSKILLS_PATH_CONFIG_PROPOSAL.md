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

- **Tier 1 — tracked in git, durable project-level state.** Plans (`<NAME>_PLAN.md` — user-authored or `/draft-plan`-generated then user-edited; the only artifact users routinely *open*). Issue trackers (`ISSUES_PLAN.md`, `BUILD_ISSUES.md`, `DOC_ISSUES.md`, `QE_ISSUES.md` — skill-appended; mirror GitHub issues by number; users typically interact via the GitHub issue, not the local file). Common structural property: persists across the project's lifetime, referenced by stable identifiers (plan slug, issue number) from PRs and other Tier 1 files. Common property NOT claimed: that humans frequently open these files directly (only plans hit that bar; trackers are mostly machine-managed).
- **Tier 2 — forensic exhaust / skill-to-skill plumbing / regenerated indexes.** Per-phase plan reports (`reports/plan-{slug}.md`), verify reports, briefing snapshots, `SPRINT_REPORT.md`/`FIX_REPORT.md` (skill-to-skill state read primarily by `/fix-report`, viewable via the dashboard), `PLAN_REPORT.md`/`VERIFICATION_REPORT.md`/`PLAN_INDEX.md` (regenerated indexes). Common property: regenerable, append-only forensic, or skill-internal plumbing; cross-references from plan files (~13 cite `PLAN_INDEX.md`) are rewritten in Phase 5b, so plan-file stability is preserved — but the underlying index file itself is gitignored regenerated state, not authored content.

**On `PLAN_INDEX.md` specifically (revised 2026-05-07):** initially classified as Tier 1 in this proposal; reclassified to Tier 2 during plan amendment after recognizing it shares the regenerated-index shape with `PLAN_REPORT.md` and `VERIFICATION_REPORT.md`. The "stable cross-reference" property of Tier 1 IS preserved because Phase 5b's cross-reference rewriter updates the ~13 plan-file references to the new `.zskills/audit/PLAN_INDEX.md` location automatically. Consumer-visible cost: PLAN_INDEX is now gitignored (no PR signal on plan-status flips); mitigation: dashboard surfaces plan status; `/work-on-plans` already has a frontmatter-scan fallback for missing INDEX (gracefully handles fresh clones until first `/plans rebuild`).

Tier 1 gets one config knob. Tier 2 has a fixed location. Reasoning: (a) within each tier, sub-dividing into per-leaf keys is bikeshedding without a real user need; (b) the tracked-vs-gitignored split that motivates flexibility is structural, not configurable — it falls out of the tier boundary; (c) a single knob keeps the consumer's mental model small while solving the actual user complaint (plans visibility).

## Proposed shape

```json
{
  "output": {
    "plans_dir": "docs/plans",
    "issues_dir": ".zskills/issues"
  }
}
```

**Default layout:**

```
docs/                             # default plans_dir; configurable; tracked in git
  plans/
    {NAME}_PLAN.md

.zskills/                         # gitignored
  issues/                         # default issues_dir; configurable
    ISSUES_PLAN.md
    BUILD_ISSUES.md
    DOC_ISSUES.md
    QE_ISSUES.md
  audit/                          # fixed location, dashboard-viewable
    plan-{slug}.md
    verify-{scope}.md
    briefing-{ts}.md
    new-blocks-{slug}.md
    SPRINT_REPORT.md
    FIX_REPORT.md
    PLAN_REPORT.md
    VERIFICATION_REPORT.md
    PLAN_INDEX.md                 # regenerated by /plans rebuild (Tier 2)
  tracking/$PIPELINE_ID/...
  monitor-state.json (+ .lock)
  work-on-plans-state.json
  dashboard-server.{pid,log}
  dev-server.{pid,log}            # was top-level var/dev.{pid,log}; flat to match dashboard
  stub-notes/
```

**Override examples:**

- `plans_dir: "plans"` — old top-level location
- `plans_dir: ".zskills/plans"` — fully hide plans inside zskills' corner
- `plans_dir: "../external-plans/zskills"` — out-of-tree (advanced)
- `issues_dir: "docs/issues"` — surface trackers next to plans
- `issues_dir: ".zskills/audit"` — cohabit with forensic reports

**Top-level zskills footprint after migration:** `docs/plans/` (or wherever `plans_dir` points) and `.zskills/`, plus `.gitignore`/`CLAUDE.md` modifications. Six legacy top-level entries removed (`SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`, `reports/`, `var/`); legacy `plans/` is moved to the new default `docs/plans/` (or wherever the user set `plans_dir`).

## Resolved decisions

**D1. Issue trackers get a separate `issues_dir` key, defaulting to `.zskills/issues/`.** Trackers are skill-appended GitHub-issue mirrors — closer in nature to forensic state than to user-authored plans. Defaulting them gitignored under `.zskills/` is the right shape: GitHub is the canonical source, the local file is convenience. The separate key lets users override to `docs/issues/` (surface alongside plans), back into `plans_dir` (if they want trackers cohabit), or to `.zskills/audit/` (cohabit with forensic). Cost of the separate key vs. cohabiting with plans: one extra config field, one extra env var (`$ZSKILLS_ISSUES_DIR`) — negligible.

**D2. Plans default to `docs/plans/` from repo root — visible, tracked, namespaced under `docs/`.** Plans are the one zskills artifact users routinely open and edit; they belong in a discoverable location that fits common project conventions (`docs/decisions/`, `docs/runbooks/`, `docs/plans/`). Repo-root `plans/` is preserved as a one-line override (`plans_dir: "plans"`) for users who want them at top level. Pre-backcompat posture (per project memory: "zskills is pre-backwards-compat") means we ship the right default rather than the legacy default. The migration step relocates existing top-level `plans/` to `docs/plans/` automatically.

## Implementation surface

**Helper: `scripts/zskills-paths.sh`** — sourceable shim, reads `output.plans_dir` and `output.issues_dir` from `.claude/zskills-config.json` via established bash-regex JSON-read pattern (no jq, per project convention). Exports:

```
ZSKILLS_PLANS_DIR        # config-resolved, absolute (default $MAIN_ROOT/docs/plans)
ZSKILLS_ISSUES_DIR       # config-resolved, absolute (default $MAIN_ROOT/.zskills/issues)
ZSKILLS_AUDIT_DIR        # fixed: $MAIN_ROOT/.zskills/audit
```

Resolves relative to caller-supplied `$MAIN_ROOT` or `$WORKTREE_PATH` — never `pwd`. Critical for `/run-plan` PR mode where the same logical path resolves both in the worktree (where commits land on the feature branch) and on main (where the post-merge state matches).

**Conformance test** — extends `scripts/test-all.sh` with grep across all skills/scripts/hooks for hardcoded literals: `SPRINT_REPORT`, `FIX_REPORT`, `PLAN_REPORT`, `VERIFICATION_REPORT`, `^plans/`, `^reports/`, `"reports/`, `"plans/`, `BUILD_ISSUES`, `DOC_ISSUES`, `QE_ISSUES`, `ISSUES_PLAN`. Any match outside doc text or the helper itself fails the suite. Same shape as the existing model-dispatch / no-jq conformance tests.

**Reader/writer surface:**

Writers (must source helper, write to resolved paths):

- `/run-plan` — `$ZSKILLS_PLANS_DIR/<NAME>_PLAN.md` (mutate frontmatter), `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`, `$ZSKILLS_AUDIT_DIR/PLAN_REPORT.md`, `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` (already-landed updates)
- `/fix-issues` — `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`, `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md`
- `/fix-report` — `$ZSKILLS_AUDIT_DIR/FIX_REPORT.md`, mutates `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`
- `/verify-changes` — `$ZSKILLS_AUDIT_DIR/verify-{scope}.md`, `$ZSKILLS_AUDIT_DIR/VERIFICATION_REPORT.md`
- `/draft-plan`, `/refine-plan` — `$ZSKILLS_PLANS_DIR/<NAME>_PLAN.md`
- `/plans` — `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` (regenerated index — Tier 2)
- `/qe-audit` — `$ZSKILLS_ISSUES_DIR/QE_ISSUES.md`
- `/add-block` — `$ZSKILLS_ISSUES_DIR/BUILD_ISSUES.md`, `$ZSKILLS_AUDIT_DIR/new-blocks-{slug}.md`
- `/add-example` — `$ZSKILLS_ISSUES_DIR/DOC_ISSUES.md`
- `/briefing report` — `$ZSKILLS_AUDIT_DIR/briefing-{ts}.md`

Readers (must source helper, read from resolved paths):

- `/briefing` (scans `$ZSKILLS_PLANS_DIR` + `$ZSKILLS_AUDIT_DIR` + `$ZSKILLS_ISSUES_DIR`; was scanning root + `reports/`)
- `/work-on-plans` (reads `$ZSKILLS_AUDIT_DIR/PLAN_INDEX.md` with frontmatter-scan fallback for missing INDEX)
- `/fix-report` (reads `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`)
- `/run-plan` (reads `$ZSKILLS_PLANS_DIR/<NAME>_PLAN.md`)
- `/refine-plan` (reads `$ZSKILLS_PLANS_DIR/<NAME>_PLAN.md`)
- `briefing.cjs` / `briefing.py` (root `*REPORT*.md` scan must move to audit dir)
- **zskills-dashboard** — first-class consumer; viewer URLs (`/viewer/?file=...`) must resolve through the helper. Already reads `.claude/zskills-config.json` (mutates dashboard block at runtime), so config access is established.

**Gitignore** — `/update-zskills` appends `.zskills/audit/`, `.zskills/issues/` (the latter only if `issues_dir` resolves under `.zskills/`; if user pointed it at `docs/issues/` or similar, leave the directory tracked). Removes the obsolete top-level `var/` line. Existing `.zskills/tracking/` line stays.

## Migration

zskills is pre-backwards-compat: ship the right default, migrate cleanly, no legacy-mode flag. Two complementary forms:

**Form A — `/update-zskills --migrate-paths` (deterministic script):**

1. Detect existing top-level artifacts (`SPRINT_REPORT.md`, `FIX_REPORT.md`, `PLAN_REPORT.md`, `VERIFICATION_REPORT.md`, `reports/`, `plans/`, `var/`, `BUILD_ISSUES.md`/`DOC_ISSUES.md`/`QE_ISSUES.md`/`ISSUES_PLAN.md` if present at root or under legacy `plans/`).
2. Move forensic + narrative reports → `.zskills/audit/`.
3. Move `plans/<NAME>_PLAN.md` → resolved `$ZSKILLS_PLANS_DIR/` (default `docs/plans/`, or whatever the user set). Move `plans/PLAN_INDEX.md` → fixed `.zskills/audit/PLAN_INDEX.md` (Tier 2 regenerated index).
4. Move `plans/{ISSUES_PLAN,BUILD_ISSUES,DOC_ISSUES,QE_ISSUES}.md` → resolved `$ZSKILLS_ISSUES_DIR/` (default `.zskills/issues/`).
5. Move `var/dev.pid` → `.zskills/dev-server.pid`, `var/dev.log` → `.zskills/dev-server.log`. Remove the now-empty `var/` directory. Update the installed `start-dev.sh` and `stop-dev.sh` stubs to reference the new paths only if they match shipped defaults (preserve user customizations).
6. Update `.gitignore`: add `.zskills/audit/`, conditionally `.zskills/issues/` (only if `issues_dir` resolves under `.zskills/`), remove the obsolete `var/` line.
7. Write `.pre-paths-migration` backup marker (mirrors existing `.pre-zskills-migration` pattern for CLAUDE.md).
8. Update any plan files containing absolute or `plans/`-prefixed cross-references to other plans or `reports/plan-*.md` files. Bash-regex rewrite scoped to `<NAME>_PLAN.md` files only; preserve user prose.
9. Print summary of moves and a one-line agent-handoff hint for any non-default-path customizations the migration declined to touch.

**Form B — agent-runnable upgrade prompt:**

For consumers whose stubs or plans contain non-default customizations the script declined to touch, ship a documented agent prompt in CHANGELOG / `references/path-config-upgrade.md` that an agent can run inside the project to safely complete edits the deterministic step skipped. Pattern: "Read `start-dev.sh`. If it writes to `var/dev.pid`, update the path to `.zskills/dev-server.pid` and adjust accordingly. If you see customization, surface diff and ask the user before editing." This handles the long tail without forcing the script to do AI-level discrimination.

## Compatibility with existing `.zskills/` usage

Adding `.zskills/issues/`, `.zskills/audit/`, and the flat `dev-server.{pid,log}` files alongside the existing `tracking/`, `monitor-state.json`, `dashboard-server.{pid,log}`, `work-on-plans-state.json`, `stub-notes/`, `tier1-migration-deferred`, `triggers/` is structurally safe. Verified by independent agent audit (six claims, all VERIFIED) on 2026-04-30:

1. **`clear-tracking.sh` is `tracking/`-scoped only.** `TRACKING_DIR="$MAIN_ROOT/.zskills/tracking"` at line 12; every `find`/`rm` operation rooted at `$TRACKING_DIR` (lines 32, 58, 99, 141, 146, 150, 162). Sibling subdirs are unreachable.

2. **Hook protection is `tracking/`-scoped only.** `hooks/block-unsafe-project.sh.template:201` regex anchors to the literal `\.zskills/tracking`. No broader `.zskills` fence exists. **This is the one caveat**: `rm -rf .zskills/issues` or `rm -rf .zskills/audit` would currently pass the hook. Once `.zskills/` holds issue trackers (skill-managed but durable), forensic audit history, and runtime state, the whole tree is load-bearing. Phase 1 deliverable: broaden the hook regex from `\.zskills/tracking` to `\.zskills` so any recursive delete targeting any `.zskills/` subdir is fenced.

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

1. **Helper + config schema + hook fence** — `scripts/zskills-paths.sh` exporting `$ZSKILLS_PLANS_DIR`, `$ZSKILLS_ISSUES_DIR`, `$ZSKILLS_AUDIT_DIR`. Schema entries for `output.plans_dir` and `output.issues_dir` in `.claude/zskills-config.schema.json`. Conformance test for hardcoded literals. **Broaden `block-unsafe-project.sh.template:201` recursive-delete regex from `.zskills/tracking` to `.zskills`** (the whole tree is load-bearing once it holds issues + audit history alongside tracking + runtime state).
2. **Writer migration** — every skill listed above, source helper, replace literals. Mirror to `.claude/skills/`.
3. **Reader migration** — every skill listed above, plus `briefing.cjs`/`briefing.py` and dashboard server.
4. **Dashboard viewer** — path-aware URL resolution; viewer URLs computed from `$ZSKILLS_*_DIR` not hardcoded.
5. **`/update-zskills --migrate-paths`** — deterministic one-shot migration with `.pre-paths-migration` backup marker.
6. **Agent-runnable upgrade prompt** — documented in `references/path-config-upgrade.md` for the long tail of customizations the deterministic step declines to touch (e.g., user-modified `start-dev.sh`).
7. **Gitignore update** — through `/update-zskills` (conditional `.zskills/issues/` line based on whether `issues_dir` resolves under `.zskills/`).
8. **Self-migration** — apply `--migrate-paths` to zskills repo itself; verify `git ls-files` no longer surfaces top-level reports, that `docs/plans/` exists, that `.zskills/issues/` and `.zskills/audit/` are populated.
9. **Documentation** — update CLAUDE.md, CHANGELOG, any skill docs that reference the old paths.

Conformance test from Phase 1 gates every subsequent phase. Existing canaries (CANARY1–11) re-run on PR to catch path-resolution regressions in `/run-plan` PR mode and parallel pipelines specifically.
