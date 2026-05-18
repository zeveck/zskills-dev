---
issue: 217
title: Reports Dir Migration — Drive .zskills/ to Zero Force-Tracked
created: 2026-05-18
status: active
---

# Plan: Reports Dir Migration — Drive .zskills/ to Zero Force-Tracked

> **Landing mode: PR** — This plan targets PR-based landing. All phases run in a named worktree on a feature branch; the final landing dispatches `/land-pr` from main. Per `.claude/zskills-config.json` `execution.landing == "pr"` + `main_protected: true`.

## Overview

Issue #217 identifies a hybrid in `.zskills/audit/`: the directory is gitignored (umbrella `.zskills/` since PR #296), yet **57 files inside it are force-tracked** because PR #211's `git mv` preserved their tracking through the path migration. Most of those force-tracked files are agent-written **work-trail artifacts** that semantically belong with `docs/plans/` and `docs/issues/` — per-plan execution reports (`plan-{slug}.md`), verify-changes outputs (`verify-{name}.md`, `verify-last-{N}.md`), and the `/fix-issues` sprint roll-up (`SPRINT_REPORT.md`). A second class — historical one-offs from the SKILL-restructure forensic sweep — should be untracked entirely because they're stale and `.zskills/` is the right home for forensic exhaust (it's already gitignored).

This plan closes that hybrid by:

1. Adding `output.reports_dir` (configurable; default `docs/reports`) as a sibling of the existing `output.plans_dir` / `output.issues_dir` schema fields. Helper `zskills-paths.sh` exports `ZSKILLS_REPORTS_DIR` from the new key (legacy fallback `.zskills/audit` preserves silent back-compat for any unaware consumer).
2. Switching the three known force-tracked writer classes (`/run-plan` plan-report, `/verify-changes` verify-report, `/fix-issues` SPRINT_REPORT) to write under `$ZSKILLS_REPORTS_DIR`. All other audit writers (briefing daily files, work-on-plans state, add-block outputs, forensic dumps) continue writing to the hardcoded `$ZSKILLS_AUDIT_DIR` — coexistence, not subsumption.
3. Migrating the 44 already-tracked work-trail files (`git mv` to the new default location, history-preserving) and untracking the 13 remaining files via `git rm --cached` (leaves on disk; umbrella `.zskills/` keeps them ignored thereafter). The 13 split as 7 audit one-offs + 6 stray `.zskills/tracking/run-plan.dashboard-tabs-and-rename/*` markers — reconciliation vs the research's 51 number: the research counted `.zskills/audit/` only; the 6 stray tracking markers under `.zskills/tracking/` were verified separately (`git ls-files .zskills/tracking/ | wc -l == 6` at draft time). WI 3.1 recomputes both numbers live; the plan handles drift dynamically (see DA-10 fix).
4. Locking the invariant via a new conformance assertion: `git ls-files .zskills/ | wc -l == 0`.

The end state: `.zskills/` is a uniform, fully-gitignored umbrella; the 44 work-trail files live at the same tier as `docs/plans/` and `docs/issues/`; consumers get a sensible default (`docs/reports/`) and can override via `output.reports_dir` if they want a different location.

## Locked Decisions

1. **Coexistence, not subsumption.** Add a new `output.reports_dir` config field (configurable, default `docs/reports`). `ZSKILLS_AUDIT_DIR` stays hardcoded at `$ROOT/.zskills/audit` for ephemeral/forensic content (`briefing-<date>.md`, work-on-plans state, debug dumps, etc.). No renaming, no env-var subsumption.
2. **Default location: `docs/reports/`.** Parallel with `docs/plans/` and `docs/issues/` — the "one bucket per output kind" precedent set by `ZSKILLS_PATH_CONFIG.md`. Not the nested `docs/plans/reports/` (breaks the parallel pattern).
3. **Three writer classes switch to `$ZSKILLS_REPORTS_DIR`:**
   - `/run-plan` `plan-{slug}.md`
   - `/verify-changes` `verify-{scope-slug}.md` and `verify-last-{N}.md`
   - `/fix-issues` `SPRINT_REPORT.md`
4. **File disposition for the 57 tracked files:**
   - **MOVE (44):** 38 × `plan-*.md` + 5 × `verify-*.md` + 1 × `SPRINT_REPORT.md` → `git mv` to the default reports_dir.
   - **UNTRACK (13):** 7 historical audit one-offs (`SKILL_VERSION_PRETOOLUSE_HOOK-followups.md`, `VERIFIER_AGENT_FIX-anthropic-issue-draft.md`, `baseline-pre-restructure.md`, `migration-warnings.md`, `post-restructure-verification.md`, `post-restructure-verification-plan.md`, `restructure-readiness.md`) + 6 stray `.zskills/tracking/run-plan.dashboard-tabs-and-rename/*` markers → `git rm --cached` (files stay on disk; umbrella `.zskills/` keeps them ignored).
5. **End-state conformance: `git ls-files .zskills/ | wc -l == 0`.** Asserted in `tests/test-skill-conformance.sh` near the existing skill-dir cleanliness block (~line 2000-2010).
6. **Migration commit shape: single commit for the file-move step.** All 44 `git mv` + 13 `git rm --cached` happen in one commit at the start of Phase 3. Rationale: history-walk clarity, atomic relative to live `SPRINT_REPORT.md` writes, and the disposition decision was already centralized in this plan. Phase 2 commits (per-skill writer/reader edits) remain separate so per-skill blame stays useful.
7. **Frozen cross-refs preserved as-is.** ~19 references to `reports/plan-*.md` exist in tracked `docs/plans/*.md` files (frozen completed plans). They self-heal at the new default location (`docs/reports/plan-*.md` resolves once files exist there). Do NOT rewrite frozen plan references — `path-config-upgrade.md` task 3 doctrine (the migration-warnings doctrine) governs: completed + non-canary plan refs stay preserved, upgrade-prompt sweep handles them post-migration if needed.
8. **`migrate-paths.sh` extension: BOTH-OR-NEITHER → BOTH-OR-ALL-OR-NEITHER (3-tuple).** Extend `write_output_block()` (lines 767-910) to a 3-positional-arg signature `(plans, issues, reports)` with 6 coordinated edits per the codebase research. Do NOT design a separate `write_reports_block()` — the BOTH-OR-NEITHER atomic-write invariant is load-bearing for crash recovery; extending it to a 3-tuple preserves it.
9. **No `.gitignore` change.** The umbrella `.zskills/` line (4) already covers everything that needs to stay ignored. `docs/reports/` is outside `.zskills/` and is force-tracked-by-virtue-of-being-`git add`-able with no negative ignore rule needed.
10. **`.pre-paths-migration` audit trail reused.** Existing 105-line TSV at repo root; `migrate-paths.sh` already appends to it (idempotent trailer pattern). The new migration must reuse, not create a parallel file.

## What this plan does NOT do

- Does not subsume or rename `ZSKILLS_AUDIT_DIR`. Briefing daily files, work-on-plans state files, add-block outputs, scratch verify reports, and all other audit writers continue writing to `$ZSKILLS_AUDIT_DIR` (still hardcoded at `.zskills/audit`, still gitignored).
- Does not rewrite frozen plan cross-references. The ~19 `reports/plan-*.md` tokens in `docs/plans/*.md` of completed plans stay as-is; they self-resolve once files exist at `docs/reports/plan-*.md`. Active-status plans get rewritten as part of their own work, not this migration.
- Does not change the `migrate-paths.sh` atomic-write contract. Extends BOTH-OR-NEITHER to BOTH-OR-ALL-OR-NEITHER — preserves the invariant by widening it, never bolts on a separate write path.
- Does not change `.gitignore`. The umbrella line already covers the right shape.
- Does not pause `/fix-issues` cron. `SPRINT_REPORT.md` write is ~seconds; the single migration commit is atomic. Quiescence isn't required (a worst-case race would land a post-mv `SPRINT_REPORT.md` write at the legacy path, which the Phase 2 writer-swap fixes structurally; the migration commit and the writer swap are committed as one PR so production is never in a partial state).
- Does not add a separate `output.scratch_dir` knob. Scope-creep deferred per locked decision 1.
- Does not triage every audit writer for force-tracking risk. The 6+ additional audit writers (add-block, work-on-plans, plans, briefing-daily) are verified not-force-adding in research; if a future regression surfaces, it's a separate plan.
- Does not bypass any hook (`--no-verify` is prohibited per CLAUDE.md). Does not call `gh pr create` or `gh pr merge --auto` directly — uses `/land-pr` dispatch.

## Acceptance Criteria (plan-level)

- [ ] AC-P.1 — End state: `git ls-files .zskills/ | wc -l` returns `0` AT MIGRATION TIME (the `tests/zskills-tracked-allowlist.txt` file is empty by design at this PR). Post-migration, the conformance test runs against the allow-list (currently empty) — see WI 3.6. The `.zskills/` umbrella is fully gitignored with zero force-tracked files at the merge time of this PR.
- [ ] AC-P.2 — `output.reports_dir` is a recognized config key. `bash skills/update-zskills/scripts/zskills-paths.sh; echo "$ZSKILLS_REPORTS_DIR"` (sourced, with `.claude/zskills-config.json` containing `"reports_dir": "docs/reports"`) prints `$ROOT/docs/reports`. Absent key → fallback `$ROOT/.zskills/audit` (silent legacy compat).
- [ ] AC-P.3 — `bash tests/run-all.sh` exits 0; `bash tests/test-skill-conformance.sh` exits 0; `bash tests/test-zskills-paths.sh` exits 0; `bash tests/test-update-zskills-paths-migration.sh` exits 0.
- [ ] AC-P.4 — Every touched source skill has a bumped `metadata.version` AND a byte-identical mirror under `.claude/skills/<name>/` for GIT-TRACKED content. Verification (mirrors `test-skill-conformance.sh:1965-1971` which uses `git ls-files` for the same reason — `__pycache__/*.pyc` would otherwise spuriously diff on every Python skill):
  ```bash
  for s in run-plan verify-changes fix-issues briefing fix-report update-zskills zskills-dashboard; do
    diff -rq --exclude=__pycache__ --exclude='*.pyc' skills/$s .claude/skills/$s
  done
  ```
  Returns empty for each. (DA-2: bare `diff -rq` produces false positives because `__pycache__/*.pyc` materializes whenever Python runs; exclude is mandatory.)
- [ ] AC-P.5 — Frozen plan cross-references (`reports/plan-*.md` in `docs/plans/*.md` with `status: complete`) are UNCHANGED relative to `main`. Verification: `git diff origin/main -- docs/plans/ | grep -E '^[+-].*reports/plan-' | wc -l` returns 0.
- [ ] AC-P.6 — Frozen plan cross-references RESOLVE at the new default location FOR REFERENCES IN THE MOVE LIST. Every `reports/plan-X.md` referenced from a tracked `docs/plans/*.md` AND present in the 38-file move list exists at `docs/reports/plan-X.md` after the migration commit lands. Pre-existing dead refs (e.g., `reports/plan-canary-5.md`, `reports/plan-foo.md` — verified pre-existing dead on `main`) are EXCLUDED. Verification (compute move-list dynamically, exclude pre-existing-dead):
  ```bash
  # Build the set of plan slugs actually being moved.
  moved=$(git ls-files .zskills/audit/plan-*.md | xargs -n1 basename | sort -u)
  broken=0
  for ref in $(grep -hoE 'reports/plan-[a-z0-9-]+\.md' docs/plans/*.md | sort -u); do
    base=$(basename "$ref")
    if echo "$moved" | grep -qx "$base"; then
      [ -f "docs/$ref" ] || { broken=$((broken+1)); echo "BROKEN-IN-MOVE-SET: $ref"; }
    fi
  done
  echo "broken=$broken"
  ```
  Expect `broken=0`. Pre-existing dead refs (refs to plans that were never executed) are documented in WI 3.10 below and intentionally untouched per locked decision 7.
- [ ] AC-P.7 — No file moved or untracked in this plan retains a tracked entry under `.zskills/audit/`. Verification: `git ls-files .zskills/audit/ | wc -l` returns 0.
- [ ] AC-P.8 — `migrate-paths.sh` 3-tuple atomic-write invariant holds: a config with ANY of the three keys (`plans_dir`, `issues_dir`, `reports_dir`) missing receives ALL THREE on next run. Verification: `tests/test-update-zskills-paths-migration.sh` extended case `case_3_partial_reports_missing` (Phase 1) passes.
- [ ] AC-P.9 — `.pre-paths-migration` audit trail records the new migration mappings (all `plan-*/verify-*/SPRINT_REPORT` moves — current count is 44, recomputed live by WI 3.1) as appended trailer lines; not a separate parallel file. Verification: `tail -200 .pre-paths-migration | grep -cE '\.zskills/audit/(plan-|verify-|SPRINT_REPORT)'` returns ≥ the live move count captured in WI 3.1.

- [ ] AC-P.11 — `migrate-paths.sh` is idempotent on a fully-migrated config: running it twice in a row produces no diff in `.claude/zskills-config.json` on the second run. Verification:
  ```bash
  # Snapshot, run migrator, snapshot, run again, snapshot, compare.
  cp .claude/zskills-config.json /tmp/cfg-before.json
  bash skills/update-zskills/scripts/migrate-paths.sh
  cp .claude/zskills-config.json /tmp/cfg-after1.json
  bash skills/update-zskills/scripts/migrate-paths.sh
  cp .claude/zskills-config.json /tmp/cfg-after2.json
  diff /tmp/cfg-after1.json /tmp/cfg-after2.json
  ```
  Second diff is empty.

- [ ] AC-P.12 — `migrate-paths.sh` emits VALID JSON when injecting a missing `reports_dir` into an existing `output: { plans_dir, issues_dir }` object. The injected key has no trailing comma after the closing brace. Verification: after running the migrator on a fixture with `{plans_dir, issues_dir}` present (no `reports_dir`), parse the result with Python:
  ```bash
  python3 -c "import json,sys; json.load(open('<fixture>/.claude/zskills-config.json'))" && echo OK
  ```
  Exits 0. (Fixes DA-5: the awk's `if (!wrote_reports) print indent ... reports ...,` injection before the closing brace must use the trailing-comma management logic described in WI 1.6 part d, not unconditional comma.)
- [ ] AC-P.10 — The plan-landing PR body does NOT contain a GitHub auto-close directive against any GH issue OTHER than #217 (the issue this plan does close). Verification (POSIX ERE — no PCRE lookahead since `grep -E` does not support `(?!...)`):
  ```bash
  gh pr view <plan-PR> --json body -q '.body' \
    | grep -ioE '(close[sd]?|fixe[sd]?|resolve[sd]?) #[0-9]+' \
    | grep -v '#217' | wc -l
  ```
  Returns 0. (`grep -P` works on GNU grep but isn't POSIX; the two-stage extract-then-filter form is portable and is what the verifier should run.)

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Config field + helper + migrator extension | ✅ | `e86458b` | Schema + zskills-paths.sh + migrate-paths.sh 3-tuple + path-tests cases 10-12; +20 tests; latent single-line `{...}` bug surfaced + fixed (case h) |
| 2 — Writer + reader path swap across affected skills | ✅ | `3b942cb..547a182` | 9 commits (7 planned + 2 Tier-1 cohabitation fix-ups caught in-flight per #380 lesson); 50 REPORTS_DIR writes, 30 legit AUDIT_DIR preserved; mirror byte-equal; 3316/3316 tests |
| 3 — Migration commit + conformance + final version bumps | ⬚ | | 44 `git mv` + 13 `git rm --cached` + `tests/test-skill-conformance.sh` new assertion + any residual version-bumps |

## Design & Constraints (plan-wide)

### Mirror discipline

For every source skill edited, the `.claude/skills/<name>/` mirror must remain byte-identical. Use `bash scripts/mirror-skill.sh <name>` at the end of each per-skill edit cluster — NOT per-file Edits to `.claude/skills/`. Per the memory anchor `feedback_claude_skills_permissions.md`: editing under `.claude/skills/` triggers permission storms; mirror via the script.

### Skill versioning (mandatory bump on every SKILL.md or sub-file edit)

Per CLAUDE.md `## Skill versioning`: every edit under `skills/<name>/` MUST bump `metadata.version` in `skills/<name>/SKILL.md` via the canonical recipe:

```bash
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
HASH=$(bash scripts/skill-content-hash.sh skills/<NAME>)
bash scripts/frontmatter-set.sh skills/<NAME>/SKILL.md metadata.version "$TODAY+$HASH"
bash scripts/mirror-skill.sh <NAME>
git add skills/<NAME>/SKILL.md .claude/skills/<NAME>/SKILL.md
```

Four enforcement layers will block stale versions: `warn-config-drift.sh` (Edit-time warn), `/commit` Phase 5 step 2.5 (hard stop), `test-skill-conformance.sh` (CI gate), `block-stale-skill-version.sh` (PreToolUse on every `git commit`). Bump per phase that touches a skill's source.

### Skills touched (final list, by phase)

- **Phase 1:** `update-zskills` (zskills-paths.sh + migrate-paths.sh + SKILL.md prose for new field documentation if any; bump if SKILL.md prose changes — likely yes via `references/path-config-upgrade.md` mention).
- **Phase 2:** `run-plan`, `verify-changes`, `fix-issues`, `briefing` (+ `briefing.py`), `fix-report`, `zskills-dashboard` (collect.py only — not a "skill" requiring SKILL.md bump but mirror-byte-identical applies). Negative-assertion prose updates in `do/SKILL.md` and `investigate/SKILL.md` (just rename `$ZSKILLS_AUDIT_DIR/plan-*` → `$ZSKILLS_REPORTS_DIR/plan-*` literals in those negative assertions — those skills don't write reports, but their phrasing must stay accurate).
- **Phase 3:** Polish-rebump for any skill whose mirror became stale; final `update-zskills` version sweep.

The dispatcher's research and the codebase footprint research already enumerated additional consumer skills (`add-block`, `work-on-plans`, `plans`, `draft-plan`, `draft-tests`, `refine-plan`) — those write to AUDIT_DIR not REPORTS_DIR (per locked decision 1), so they are NOT touched by this plan unless their prose mentions `plan-{slug}.md`/`verify-{name}.md`/`SPRINT_REPORT.md` patterns that semantically move to reports_dir. Per-hit triage at implementation time using the rule: writer-class file pattern (`plan-*`, `verify-*`, `SPRINT_REPORT`) → reports_dir; everything else (`briefing-*`, `work-on-plans-*`, `NEW_BLOCKS_REPORT`, `PLAN_INDEX`, debug dumps) stays audit_dir.

### Audit-vs-reports triage rule (for ambiguous per-hit cases)

When swapping `$ZSKILLS_AUDIT_DIR` references in Phase 2, classify each hit by the FILENAME PATTERN it references, not the skill:

| Filename pattern referenced | Goes to | Reason |
|---|---|---|
| `plan-{slug}.md`, `plan-*.md` | `$ZSKILLS_REPORTS_DIR` | Run-plan work-trail |
| `verify-{name}.md`, `verify-*.md`, `verify-last-*.md` | `$ZSKILLS_REPORTS_DIR` | Verify-changes work-trail |
| `SPRINT_REPORT.md` | `$ZSKILLS_REPORTS_DIR` | Fix-issues sprint roll-up |
| `briefing-{date}.md`, `briefing-*.md` | `$ZSKILLS_AUDIT_DIR` | Daily briefing (still ephemeral) |
| `work-on-plans-{id}.md` | `$ZSKILLS_AUDIT_DIR` | Sprint state |
| `NEW_BLOCKS_REPORT.md`, `new-blocks-{slug}.md` | `$ZSKILLS_AUDIT_DIR` | Block-diagram outputs (out of scope for this plan; just leave audit refs) |
| `PLAN_INDEX.md` | `$ZSKILLS_AUDIT_DIR` | Index (regenerated, ephemeral) |
| `VERIFICATION_REPORT.md`, `PLAN_REPORT.md`, `FIX_REPORT.md` | `$ZSKILLS_AUDIT_DIR` | Roll-up indices (regenerated; not migrated by this plan) |
| Generic forensic / debug | `$ZSKILLS_AUDIT_DIR` | Default |

This table is also the source of truth that the verifier should grep against when checking Phase 2 didn't over-swap.

### Hot-path: `SPRINT_REPORT.md` — implementer MUST pause cron before WI 3.3

`/fix-issues` sprint mode appends to `SPRINT_REPORT.md` every run (cron `*/10` or manual). Recent commits #359 #364 touched it. The plan's migration commit (Phase 3) does ONE `git mv .zskills/audit/SPRINT_REPORT.md docs/reports/SPRINT_REPORT.md` — atomic. The Phase 2 writer-swap is committed BEFORE Phase 3's migration so once the PR lands, both the writer path and the file location update in a single squash-merge.

**Cron-race risk (DA-8 corrects the draft's "no data loss" claim):** A live `/fix-issues` cron firing between WI 3.3 (local `git mv`) and PR merge would write a new `SPRINT_REPORT.md` at the LEGACY `.zskills/audit/` path. Once the PR lands, that legacy-path write becomes orphaned (writers now point at REPORTS_DIR; the orphan is gitignored under the umbrella so it's invisible to anyone reading the canonical location). It's not data CORRUPTION but it IS data INVISIBILITY — a sprint report effectively vanishes.

**Required mitigation:** the implementer MUST pause any active `/fix-issues` cron BEFORE running WI 3.3. This is now a hard step (WI 3.0 below), not a "courtesy" — resolves the F9 contradiction by picking the strict-implementer-pauses option uniformly. The user-pauses-cron phrasing in older drafts of this section is overridden.

### Hard constraints

- Do NOT call `gh pr create` or `gh pr merge --auto` directly. Dispatch `/land-pr` via the Skill tool. Per CLAUDE.md `## Git Rules` and PR #166 conformance lock.
- Do NOT bypass hooks (`--no-verify`). All four skill-version enforcement layers stay armed.
- Do NOT use `2>/dev/null` on fallible operations whose success matters (`git mv`, `git rm --cached`, `git status`, `mirror-skill.sh`). Verify the result of every state-changing command (`&& echo done`, not `; echo done`).
- Do NOT pipe test output. Use the canonical idiom: `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; <cmd> > "$TEST_OUT/.test-results.txt" 2>&1`. Compute `$TEST_OUT` AFTER `cd`-ing into the worktree root.
- Do NOT design a separate `write_reports_block()` in `migrate-paths.sh`. Extend `write_output_block()` to 3-tuple. The BOTH-OR-NEITHER → BOTH-OR-ALL-OR-NEITHER widening preserves the atomic-write invariant; separate functions would break it.
- Do NOT modify `.gitignore`. The umbrella `.zskills/` already covers what needs to stay ignored. `docs/reports/` is outside the umbrella and force-tracked-by-default.
- Do NOT rewrite frozen plan references (`reports/plan-*.md` in completed-status plans). Per `path-config-upgrade.md` task 3 doctrine — self-heal at the new location.
- Do NOT add `jq`. Use `BASH_REMATCH` for trivial JSON (mirror of zskills-paths.sh idiom) and Python stdlib `json` if non-trivial (per CLAUDE.md "Python is required").
- Do NOT untrack worktree changes you didn't make. `git status -s | grep '^??'` before any `git mv` or `git stash` to protect untracked files; use `git stash -u` if any are present.
- "Surface bugs, don't patch." If `migrate-paths.sh` 3-tuple extension surfaces an unrelated bug in the existing BOTH-OR-NEITHER implementation, fix it at the source — don't bolt a 4th workaround knob.
- Skill-version bumps are mandatory on every SKILL.md (or sub-file) edit. Per-phase commits each bump; Phase 3 catches verifier-polish rebumps.

### Dependencies (plan-level)

- PR #211 (origin path-config refactor, MERGED): introduced `output.plans_dir`/`output.issues_dir` schema + `migrate-paths.sh write_output_block()`. This plan extends both.
- PR #296 (issues_dir default flip, MERGED 2026-05-16): collapsed `.gitignore` to umbrella `.zskills/`. This plan relies on the umbrella to make `.zskills/audit/*` files gitignored once untracked.
- Issue #217 (filed 2026-05-10): the design issue this plan implements.

---

## Phase 1 — Config field + helper + migrator extension

### Goal

Add the `output.reports_dir` config field end-to-end: schema documentation, `zskills-paths.sh` export of `ZSKILLS_REPORTS_DIR`, `migrate-paths.sh` 3-tuple atomic-write extension, and the corresponding conformance test cases. No writer changes yet — this phase establishes the path scaffold that Phase 2 writes through. After Phase 1 lands, `bash zskills-paths.sh; echo $ZSKILLS_REPORTS_DIR` works correctly for any configured value with a sensible legacy fallback (`.zskills/audit`).

### Work Items

- [ ] WI 1.1 — Worktree setup. Use the `/create-worktree` skill (a top-level skill, not a `/draft-plan` sub-skill — reviewer F13 caught the misnomer), or accept the worktree the orchestrator landed this plan in. Confirm branch is the agreed feature branch (typical: `feat/reports-dir-migration` per `branch_prefix: "feat/"`), pushed to `origin`, and `docs/plans/REPORTS_DIR_MIGRATION.md` is committed on it.

- [ ] WI 1.2 — Schema: add `reports_dir` property to `config/zskills-config.schema.json` after `issues_dir` (line 179). Mirror the prose style of `plans_dir`/`issues_dir`:
  ```json
  "reports_dir": {
    "type": "string",
    "description": "Directory for agent-written work-trail reports: /run-plan plan-{slug}.md, /verify-changes verify-{name}.md, /fix-issues SPRINT_REPORT.md. Documented default: docs/reports. Absent → legacy .zskills/audit (silent back-compat for pre-migration consumers). Same resolution rules as plans_dir/issues_dir. Distinct from $ZSKILLS_AUDIT_DIR (briefing daily files, work-on-plans state, debug dumps — still hardcoded at .zskills/audit and gitignored)."
  }
  ```
  No `default:` JSON-schema key (matches precedent — defaults documented in prose, absence falls back to `_ZSK_PATHS_REPORTS_RAW=".zskills/audit"`).

- [ ] WI 1.3 — Default value: set `output.reports_dir: "docs/reports"` in `/workspaces/zskills/.claude/zskills-config.json` (this repo's own config; consumers get a default via the documented-default prose + migrator). Add as a sibling of the existing `plans_dir`/`issues_dir` entry in the `output` block (lines 41-44).

- [ ] WI 1.4 — `skills/update-zskills/scripts/zskills-paths.sh` extension. Six surgical edits, mirroring the existing `plans_dir`/`issues_dir` blocks:
  1. Line 52-54 pre-init: add `ZSKILLS_REPORTS_DIR=""` after the existing `ZSKILLS_AUDIT_DIR=""`.
  2. Line 57-58: add `_ZSK_PATHS_REPORTS_RAW=""` after the existing `_ZSK_PATHS_ISSUES_RAW=""`.
  3. Lines 68-73 BASH_REMATCH block: add a third stanza after the `issues_dir` block:
     ```bash
     if [[ "$_ZSK_PATHS_BODY" =~ \"output\"[[:space:]]*:[[:space:]]*\{[^}]*\"reports_dir\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[^}]*\} ]]; then
       _ZSK_PATHS_REPORTS_RAW="${BASH_REMATCH[1]}"
     fi
     ```
  4. Lines 78-79 fallback: add `[ -z "$_ZSK_PATHS_REPORTS_RAW" ] && _ZSK_PATHS_REPORTS_RAW=".zskills/audit"`. **Note the asymmetry vs. plans_dir/issues_dir**: those fall back to legacy `plans`; reports_dir falls back to the LEGACY AUDIT PATH so any pre-migration consumer (config absent reports_dir) sees zero behavior change — their existing `.zskills/audit/plan-*.md` writes continue working unchanged.
  5. Lines 86-93 case-esac: add a third block after the `issues_dir` case:
     ```bash
     case "$_ZSK_PATHS_REPORTS_RAW" in
       /*) ZSKILLS_REPORTS_DIR="$_ZSK_PATHS_REPORTS_RAW" ;;
       *)  ZSKILLS_REPORTS_DIR="$_ZSK_PATHS_ROOT/$_ZSK_PATHS_REPORTS_RAW" ;;
     esac
     ```
  6. Line 96 unset: add `_ZSK_PATHS_REPORTS_RAW` to the existing `unset` line.

  `ZSKILLS_AUDIT_DIR="$_ZSK_PATHS_ROOT/.zskills/audit"` at line 94 stays UNCHANGED (locked decision 1: coexistence).

- [ ] WI 1.5 — Mirror `zskills-paths.sh` to `.claude/skills/update-zskills/scripts/zskills-paths.sh`. Use `bash scripts/mirror-skill.sh update-zskills` (not per-file copy — the mirror script handles the whole skill).

- [ ] WI 1.6 — `skills/update-zskills/scripts/migrate-paths.sh` extension. Six coordinated edits per the codebase research:

  a) **Detection at lines 366-378.** Add `HAS_REPORTS_KEY=0` next to `HAS_PLANS_KEY=0` / `HAS_ISSUES_KEY=0`, and a third regex detector reading the existing config:
  ```bash
  if echo "$EXISTING_CFG" | grep -qE '"reports_dir"[[:space:]]*:'; then
    HAS_REPORTS_KEY=1
    EXISTING_REPORTS=$(echo "$EXISTING_CFG" | grep -oE '"reports_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*"reports_dir"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
  fi
  ```
  (Match the existing pattern at 366-378 verbatim; the implementer should re-read the exact lines and copy the idiom.)

  b) **Skip-already-migrated gate at line 384.** Extend to require all THREE keys present:
  ```bash
  if [ "$HAS_LEGACY" -eq 0 ] && [ "$HAS_PLANS_KEY" -eq 1 ] && [ "$HAS_ISSUES_KEY" -eq 1 ] && [ "$HAS_REPORTS_KEY" -eq 1 ]; then
  ```

  c) **Target resolution at lines 395-403.** Add a third block:
  ```bash
  if [ "$HAS_REPORTS_KEY" -eq 1 ] && [ -n "$EXISTING_REPORTS" ]; then
    TARGET_REPORTS="$EXISTING_REPORTS"
  else
    TARGET_REPORTS="docs/reports"
  fi
  ```

  d) **`write_output_block()` 3-tuple signature (lines 767-910) — trailing-comma-aware injection.** Change `write_output_block() { local plans="$1" issues="$2" tmp` to `local plans="$1" issues="$2" reports="$3" tmp`. The existing awk at line 820-821 emits `plans_dir + ","` and `issues_dir + ","` UNCONDITIONALLY before the closing brace — which is a latent bug today (only saved by the fact that BOTH are always missing together, so both `,` lines + the `}` form valid JSON). With the 3-tuple gate (`HAS_PLANS_KEY=1, HAS_ISSUES_KEY=1, HAS_REPORTS_KEY=0`), injecting `reports_dir + ","` before `}` yields invalid trailing-comma JSON. The fix collects missing keys, then emits them with commas BETWEEN but not AFTER the last. Specific edits, line-anchored:

  - **BEGIN block (line 781-782):** add `wrote_reports = 0`. Also pass `reports = ENVIRON["reports"]`.
  - **Existing-key replacement (after issues_dir block, ~line 805-815):** add a third parallel block:
    ```awk
    if (match(line, /"reports_dir"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
      indent = ""
      if (match(line, /^[[:space:]]*/)) indent = substr(line, 1, RLENGTH)
      tc = ""
      if (match(line, /,[[:space:]]*$/)) tc = ","
      print indent "\"reports_dir\": \"" reports "\"" tc
      wrote_reports = 1
      depth = depth + n_open - n_close
      if (depth < 0) in_output = 0
      next
    }
    ```
  - **Closing-brace injection (REPLACE the lines 820-821 unconditional `,` block):** build a list of missing keys, then emit with comma-between-not-after-last:
    ```awk
    if (match(line, /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/) && depth + n_open - n_close <= 0) {
      indent = "    "
      # Build the list of keys to inject (in canonical order: plans, issues, reports).
      n_missing = 0
      if (!wrote_plans)   { missing[++n_missing] = "\"plans_dir\": \"" plans "\"" }
      if (!wrote_issues)  { missing[++n_missing] = "\"issues_dir\": \"" issues "\"" }
      if (!wrote_reports) { missing[++n_missing] = "\"reports_dir\": \"" reports "\"" }
      # If at least one existing key was preserved (wrote_* != 0 for ANY), the last
      # preserved key already has its own trailing-comma policy. The injected keys
      # follow with commas BETWEEN every line; the LAST injected key gets a comma
      # ONLY if there's an existing-key after it (impossible at the `}` line) — so
      # last injected key gets NO trailing comma.
      for (i = 1; i <= n_missing; i++) {
        suffix = (i < n_missing) ? "," : ""
        print indent missing[i] suffix
      }
      print line
      in_output = 0
      depth = 0
      next
    }
    ```
    **CRITICAL trailing-comma edge case:** if ANY existing key (`wrote_plans` OR `wrote_issues`) was preserved, its OWN line still carries its OWN original trailing comma. To handle this cleanly: when injecting missing keys after an existing key, the existing key's last-line tc=","  is fine (it WANTS a comma because something follows it). The last injected key must have NO comma. The logic above handles this — but if the LAST EXISTING preserved key was originally the last in the object (no trailing comma), the FIRST injected key needs a leading-line context where the preserved key gets a NEWLY-ADDED comma. **The implementer MUST add a pre-pass that scans for the last-preserved-key's tc and rewrites it to "," if any injection follows.** See WI 1.6 part d-bis below.

  - **Single-line `{}` expansion (lines 845-846 — when `output: {}` is encountered):** emit three lines, with commas between but not after the last:
    ```awk
    print indent "  \"plans_dir\": \"" plans "\","
    print indent "  \"issues_dir\": \"" issues "\","
    print indent "  \"reports_dir\": \"" reports "\""
    ```
    Then set `wrote_plans = 1; wrote_issues = 1; wrote_reports = 1`.
  - **No-output insertion (lines 888-891):** emit a 3-key object, same comma policy.
  - **`awk` ENVIRON injection (lines 775 and 860-861):** add `reports="$reports"` to BOTH awk invocations' env-var preamble.

  d-bis) **Pre-pass for "preserved-key originally last" comma rewrite.** If the awk preserves an existing key (e.g., `issues_dir`) that was originally the LAST key in the object (no trailing comma), AND we then inject `reports_dir` after it, the preserved key's line is missing a comma. Two implementation options:
  - **Option A (preferred):** delay emission of the preserved-key line until the closing brace is seen; if injections follow, force a trailing comma onto the buffered line before printing.
  - **Option B:** post-process the awk output with a second pass that fixes any `"key": "value"\n}` → `"key": "value",\n<injection>\n}` pattern.

  The drafter recommends Option A — single-pass awk with a one-line buffer for the last-preserved-key. Implementer must add a test case (Case 14 in `tests/test-update-zskills-paths-migration.sh`) that constructs the exact failure shape:
  ```json
  {
    "output": {
      "plans_dir": "docs/plans",
      "issues_dir": "docs/issues"
    }
  }
  ```
  Running the migrator must produce VALID JSON containing all three keys. Validate with `python3 -c "import json; json.load(open('<cfg>'))"`.

  e) **Gate at line 914.** Extend to write-if-ANY-missing:
  ```bash
  if [ "$HAS_PLANS_KEY" -eq 0 ] || [ "$HAS_ISSUES_KEY" -eq 0 ] || [ "$HAS_REPORTS_KEY" -eq 0 ]; then
    if ! write_output_block "$TARGET_PLANS" "$TARGET_ISSUES" "$TARGET_REPORTS"; then
  ```

  f) **Summary print at lines 934-937.** Include reports_dir in the success message.

- [ ] WI 1.7 — Mirror `migrate-paths.sh` to `.claude/skills/update-zskills/scripts/migrate-paths.sh` via `bash scripts/mirror-skill.sh update-zskills`.

- [ ] WI 1.7-bis — **Standalone awk-only fixture for `write_output_block()` (Round 2 Gap B).** The 3-tuple awk extension (WI 1.6 part d + d-bis) is the highest-risk change in the plan: it modifies the existing-output-object branch (`migrate-paths.sh:773-857`) where preserved keys interact with injected keys, AND adds a one-line buffer for the last-preserved-key trailing-comma rewrite (d-bis Option A). The integration tests in `tests/test-update-zskills-paths-migration.sh` run the migrator end-to-end, but the awk-program's edge cases (which-keys-are-already-present × which-key-is-last × indent variance) deserve direct coverage with python3-validated JSON output, isolated from the surrounding bash scaffolding.

  **Fixture directory:** `tests/fixtures/migrate-paths-awk/` — each case is a triplet:
  - `<case>.input.json` — input config (the `$CFG` passed to the awk program)
  - `<case>.env` — shell file sourced before awk runs, defining `plans`, `issues`, `reports` env vars (values passed via `awk -v` or `ENVIRON[]` per the migrate-paths idiom)
  - `<case>.expected.json` — expected output (whitespace-normalized JSON; comparison uses Python `json.load + json.dumps(sort_keys=False, indent=2)` for both sides)

  **Cases to ship (a-f from the spec + g-i for shape variance):**

  | Case | Input shape | Last-existing key | Expected result |
  |------|-------------|-------------------|-----------------|
  | a — no_output | Config has NO `output` object | n/a (no-output insertion path) | Adds full 3-key `output` block via the lines-888-891 branch |
  | b — output_empty_zero_keys | `"output": {}` (single-line) | n/a (expansion path lines 838-851) | Expands to all 3 keys, comma-between-not-after-last |
  | c — output_one_key_plans | `output: {plans_dir: "x"}` only | plans_dir (last) | Adds `issues_dir`, `reports_dir`; preserved `plans_dir` line gets trailing comma added via d-bis buffer |
  | d — output_two_keys_p_i | `output: {plans_dir, issues_dir}` | issues_dir (last) | Adds `reports_dir`; preserved `issues_dir` gets trailing comma added via d-bis buffer (THE primary failure mode from DA-5 — `issues_dir` was last with NO comma; injecting after it would yield `..."issues_dir": "..."\n  "reports_dir": "..."` missing the inter-key comma) |
  | e — output_three_keys_idempotent | `output: {plans_dir, issues_dir, reports_dir}` (all 3) | reports_dir | Replaces in place, no injection; no trailing-comma rewrite needed |
  | f — output_one_key_reports_only | `output: {reports_dir}` only | reports_dir | Adds `plans_dir`, `issues_dir`; ordering policy emits in plans/issues/reports canonical order — preserved `reports_dir` line is touched (its trailing-comma policy depends on injection ordering; test pins the exact decision) |
  | g — preserved_has_trailing_comma | `output: {plans_dir: "x",\n issues_dir: "y",}` (trailing comma on last existing) | issues_dir (with `,`) | Adds `reports_dir`; d-bis buffer detects the existing comma and does NOT add a second one |
  | h — single_line_with_comma | `"output": {"plans_dir": "x"},` (single-line + trailing object comma) | plans_dir | Expansion path preserves the outer trailing comma; all 3 keys present in expanded form |
  | i — output_two_keys_p_r_missing_i | `output: {plans_dir, reports_dir}` | reports_dir | Adds `issues_dir` BETWEEN them; preserved `plans_dir` already has its comma (something followed); preserved `reports_dir` gets no comma (nothing follows the closing brace) |

  Cases a-f are the spec-mandated coverage per the Round 2 prompt; g, h, i guard the comma-state edge cases the refiner identified during d-bis design.

  **Test driver:** `tests/test-migrate-paths-awk.sh` — new test file, registered in `tests/run-all.sh`. Pseudocode:
  ```bash
  #!/bin/bash
  # tests/test-migrate-paths-awk.sh — direct unit-tests for write_output_block()'s
  # awk program(s), in isolation from the migrator's outer bash scaffolding.
  set -u
  FIXTURE_DIR="tests/fixtures/migrate-paths-awk"
  AWK_SOURCE_FILE="skills/update-zskills/scripts/migrate-paths.sh"
  PASS=0; FAIL=0
  for case_dir in "$FIXTURE_DIR"/*/; do
    case_name=$(basename "$case_dir")
    # shellcheck source=/dev/null
    . "$case_dir/env"   # sets plans, issues, reports
    # Pick the awk program based on input shape: if input has "output": { ... },
    # use the existing-output branch (lines 775-857); else the no-output branch
    # (lines 860-894). Test driver mirrors the dispatch logic.
    if grep -q '"output"[[:space:]]*:[[:space:]]*{' "$case_dir/input.json"; then
      AWK_PROG=$(sed -n '775,857p' "$AWK_SOURCE_FILE")
    else
      AWK_PROG=$(sed -n '860,894p' "$AWK_SOURCE_FILE")
    fi
    actual=$(plans="$plans" issues="$issues" reports="$reports" \
             awk "$AWK_PROG" "$case_dir/input.json")
    # Validate JSON.
    echo "$actual" | python3 -c 'import json,sys; json.load(sys.stdin)' || {
      echo "FAIL[$case_name]: output is not valid JSON"; FAIL=$((FAIL+1)); continue
    }
    # Compare canonicalized JSON.
    a_norm=$(echo "$actual" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin),sort_keys=False,indent=2))')
    e_norm=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),sort_keys=False,indent=2))' "$case_dir/expected.json")
    if [ "$a_norm" = "$e_norm" ]; then
      echo "PASS[$case_name]"; PASS=$((PASS+1))
    else
      echo "FAIL[$case_name]:"; diff <(echo "$a_norm") <(echo "$e_norm"); FAIL=$((FAIL+1))
    fi
  done
  echo "Total: PASS=$PASS FAIL=$FAIL"
  [ "$FAIL" -eq 0 ]
  ```

  **Implementer choice for AWK_PROG extraction:** the `sed -n '775,857p'` line ranges above MUST be re-anchored to the actual line numbers after WI 1.6 lands its edits. Better: factor the awk programs into separate files under `skills/update-zskills/scripts/_awk/write-output-existing.awk` and `..._no-output.awk`, source-of-truth them from there, and have `write_output_block()` call `awk -f` instead of inline-heredoc. This eliminates line-number fragility in the test driver AND makes the awk programs reviewable in their own right. The drafter recommends this refactor as part of WI 1.6 part d, but it is OPTIONAL — the inline form works if the test driver extracts ranges anchored to stable comment markers (`# --- BEGIN write-output-existing ---` / `# --- END write-output-existing ---`) instead of line numbers.

  **Pass-gate for Phase 1 closure (AC-1.14):** `bash tests/test-migrate-paths-awk.sh` exits 0; PASS count equals the number of fixture directories (9 at draft).

- [ ] WI 1.8 — `tests/test-zskills-paths.sh` extension. Add FOUR new cases (10a, 10b, 11, 12). Reviewer F4 caught the conflation: "config absent" and "config present + reports_dir key missing" are different code paths:
  - **Case 10a (config file absent entirely):** No `.claude/zskills-config.json` exists. Assert `$ZSKILLS_REPORTS_DIR == "$T10a/.zskills/audit"`. Mirrors AC-1.4.
  - **Case 10b (config present, reports_dir key absent):** Config exists with `output.plans_dir` + `output.issues_dir` BUT no `reports_dir`. Assert `$ZSKILLS_REPORTS_DIR == "$T10b/.zskills/audit"` (silent back-compat).
  - **Case 11 (custom relative):** Config has `"reports_dir": "build/audit"`. Assert `$ZSKILLS_REPORTS_DIR == "$T11/build/audit"`.
  - **Case 12 (absolute):** Config has `"reports_dir": "/abs/path/reports"`. Assert `$ZSKILLS_REPORTS_DIR == "/abs/path/reports"` (used as-is).
  - **Case 13 (malformed JSON — DA-9):** Config has `{"output": { "reports_dir": "x"` (truncated, no closing brace). Assert `$ZSKILLS_REPORTS_DIR == "$T13/.zskills/audit"` (BASH_REMATCH fallback path; the malformed config should NOT crash the helper).

- [ ] WI 1.9 — `tests/test-update-zskills-paths-migration.sh` extension. The file has **13 existing cases** (1-13, verified via `grep -nE '^case_' tests/test-update-zskills-paths-migration.sh`). DA-12 surfaced that several have post-migration JSON-shape assertions that will break under the 3-tuple gate. Enumerate each:

  | Case | Current shape assertion | Impact under 3-tuple | Action |
  |------|--------------------------|-----------------------|--------|
  | `case_1_legacy_only` | `plans_dir==docs/plans` + `issues_dir==docs/issues` | Will now ALSO have `reports_dir==docs/reports` | EXTEND: assert `reports_dir==docs/reports` |
  | `case_2_preconfigured` | `plans_dir==stash` + `issues_dir==.zskills/issues` preserved | Same keys preserved + `reports_dir` newly injected | EXTEND: assert `reports_dir==docs/reports` (default since absent pre-migration) |
  | `case_3_idempotent` | Tests second-run no-diff | The 3-tuple gate must ALSO be idempotent | EXTEND fixture: pre-set `reports_dir`; assert second-run no-diff |
  | `case_4_empty` | Empty input → adds plans_dir/issues_dir | Now adds all three | EXTEND: assert `reports_dir==docs/reports` injected |
  | `case_5_customized_stub` | Pre-set `plans_dir=stash` | Same | EXTEND: assert `reports_dir` newly injected |
  | `case_6_cross_ref_rewrite` | Cross-ref rewrite, doesn't grep plans_dir | No JSON-shape assertion | NO CHANGE |
  | `case_7_canary_self_invocation` | Canary semantics | Verify no regression on canary path | RE-RUN, NO EDIT (validates 3-tuple is canary-safe) |
  | `case_8_completed_noncanary_warn` | Warning-path | No JSON-shape | NO CHANGE |
  | `case_9_hook_rerender_gitignore` | Has `grep -q '"plans_dir"...'` per line 636-637 | Will see new `reports_dir`; if the grep is exclusive, extend | EXTEND: also assert `reports_dir` present |
  | `case_10_rewrite_only_recovery` | Recovery-only mode | Verify 3-tuple doesn't fire in recovery | RE-RUN, EXTEND only if assertions on shape exist |
  | `case_11_chmod_fallback` | Permission-handling | Independent of JSON shape | NO CHANGE |
  | `case_12_plain_plans_catchall` | Plain `plans/` directory catchall | No shape assertion typically | RE-RUN, audit-on-implementation |
  | `case_13_cross_ref_rewrite_migration_doc_guard` | Doc-guard | No JSON shape | NO CHANGE |

  - **New `case_14_partial_reports_missing` (this plan's net-new case — DA-5 + AC-P.8 + AC-P.12):** Pre-migration config has `plans_dir` + `issues_dir` set to custom values AND `reports_dir` ABSENT. Post-migration assertions:
    1. ALL THREE keys present with `plans_dir`/`issues_dir` preserved verbatim.
    2. `reports_dir == "docs/reports"` (the default).
    3. Output is VALID JSON: `python3 -c "import json; json.load(open(...))"` exits 0 (validates the trailing-comma fix in WI 1.6 part d/d-bis).

  Implementer MUST re-run all 13 existing cases after the extension and inspect each for shape-drift assertions that aren't yet covered by the table above — the table is the drafter's best-effort enumeration but each `case_N` body must be eyeballed in context.

- [ ] WI 1.10 — `skills/update-zskills/SKILL.md` prose update. Enumerated hits (verified via `grep -nE 'plans_dir|issues_dir' skills/update-zskills/SKILL.md skills/update-zskills/references/*.md`):

  | File | Line | Current text (truncated) | Action |
  |------|------|--------------------------|--------|
  | `skills/update-zskills/SKILL.md` | 43-44 | "...writes `output.plans_dir` + `output.issues_dir` LAST (atomic both-or-neither)..." | Edit to "writes `output.plans_dir` + `output.issues_dir` + `output.reports_dir` LAST (atomic both-or-all-or-neither — 3-tuple)" |
  | `skills/update-zskills/SKILL.md` | 216 | "→ docs/plans/  (or $output.plans_dir if user-set)" | Add a parallel line after the docs/issues line: "→ docs/reports/  (or $output.reports_dir if user-set; legacy fallback `.zskills/audit`)" |
  | `skills/update-zskills/SKILL.md` | 220 | "→ docs/issues/  (or $output.issues_dir if user-set)" | Use this as the anchor for the docs/reports/ line above |
  | `skills/update-zskills/SKILL.md` | 281 | Echo line in `--migrate-paths` output: `Wrote output.plans_dir = "docs/plans" and output.issues_dir = "docs/issues".` | Edit to include `output.reports_dir = "docs/reports"`. Per-skill source-of-truth for the actual printed message lives in `migrate-paths.sh` line 934-937 (WI 1.6 part f) — keep the prose mirror in sync. |
  | `skills/update-zskills/SKILL.md` | 497-498 | "Path-config keys are EXEMPT from auto-backfill. `output.plans_dir` and `output.issues_dir` MUST NOT be inserted into..." | Extend to "...`output.plans_dir`, `output.issues_dir`, and `output.reports_dir` MUST NOT be inserted into..." |
  | `skills/update-zskills/references/path-config-upgrade.md` | 54 | "existing config's `output.plans_dir`, and runs ONLY the cross-ref..." | Extend reads to include `reports_dir` in the same context |
  | `skills/update-zskills/references/script-ownership.md` | 41 | "writes output.plans_dir / output.issues_dir LAST" | Update to "writes output.plans_dir / output.issues_dir / output.reports_dir LAST (3-tuple atomic)" |

  Total: 6 edit sites across 3 files. Each edit must be byte-identical between source + mirror; the version bump in WI 1.11 will absorb all of them.

- [ ] WI 1.11 — Skill-version bump for `update-zskills` (mandatory since SKILL.md and/or references/ files in WI 1.10 changed):
  ```bash
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  HASH=$(bash scripts/skill-content-hash.sh skills/update-zskills)
  bash scripts/frontmatter-set.sh skills/update-zskills/SKILL.md metadata.version "$TODAY+$HASH"
  bash scripts/mirror-skill.sh update-zskills
  ```

- [ ] WI 1.12 — Commit + test. `git add` the schema + zskills-config.json + zskills-paths.sh (both copies) + migrate-paths.sh (both copies) + tests + SKILL.md (both copies) + references. Commit message: `feat(paths): add output.reports_dir field + ZSKILLS_REPORTS_DIR helper + 3-tuple atomic migrator (#217)`. Run the full suite per the canonical idiom:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
  Read `$TEST_OUT/.test-results.txt` to verify exit 0 + all assertions pass.

### Design & Constraints

- The fallback in WI 1.4 step 4 is asymmetric on purpose: `plans_dir`/`issues_dir` fall back to legacy `plans` (per their pre-#211 semantic); `reports_dir` falls back to `.zskills/audit` because that IS its pre-migration location. This is the silent-back-compat hinge — any consumer who never runs the migrator sees zero behavior change.
- `ZSKILLS_AUDIT_DIR` STAYS hardcoded at line 94. Two env vars coexist post-Phase-1: `ZSKILLS_AUDIT_DIR` (hardcoded, ephemeral) and `ZSKILLS_REPORTS_DIR` (configurable, work-trail). Skills decide per-write which to use.
- The 3-tuple write in `migrate-paths.sh` preserves the BOTH-OR-NEITHER invariant by extending it to BOTH-OR-ALL-OR-NEITHER. No separate `write_reports_block()` — that would break atomicity for partial-write recovery.
- Phase 1 does NOT touch any writer skill (run-plan/verify-changes/fix-issues). Those land in Phase 2.

### Acceptance Criteria

- [ ] AC-1.1 — `grep -nE '"reports_dir"' config/zskills-config.schema.json` returns ≥ 1 hit.
- [ ] AC-1.2 — `grep -nE '"reports_dir":\s*"docs/reports"' .claude/zskills-config.json` returns ≥ 1 hit.
- [ ] AC-1.3 — `grep -cE 'ZSKILLS_REPORTS_DIR' skills/update-zskills/scripts/zskills-paths.sh` returns exactly 3 (pre-init line, case-esac branch /relative/, case-esac branch /absolute/). `grep -cE '_ZSK_PATHS_REPORTS_RAW' skills/update-zskills/scripts/zskills-paths.sh` returns exactly 4 (pre-init, BASH_REMATCH assignment, fallback, unset). Mirrors identical (`diff -q skills/.../zskills-paths.sh .claude/skills/.../zskills-paths.sh` empty).
- [ ] AC-1.4 — `bash -c 'unset ZSKILLS_REPORTS_DIR; ZSKILLS_PATHS_ROOT=$(mktemp -d); source skills/update-zskills/scripts/zskills-paths.sh; echo "$ZSKILLS_REPORTS_DIR"'` ends with `/.zskills/audit` (legacy fallback when no config file is present).
- [ ] AC-1.5 — A fixture sourcing `zskills-paths.sh` with a synthetic config containing `"reports_dir":"docs/reports"` resolves `$ZSKILLS_REPORTS_DIR` to `<root>/docs/reports`. (Implemented as Case 11 in `tests/test-zskills-paths.sh`.)
- [ ] AC-1.6 — `grep -cE 'HAS_REPORTS_KEY|TARGET_REPORTS|wrote_reports|reports_dir' skills/update-zskills/scripts/migrate-paths.sh` returns ≥ 10 (DA-13: each of the two awk programs has its own BEGIN + wrote_reports init + match block + injection block, plus the bash-side detection + gate + target resolution + summary print + comma-injected key in the no-output insertion). Expected breakdown: 4 awk-internal mentions × 2 programs (8) + 4 bash-side (detection, gate, target, summary) = 12. Floor `≥ 10` allows for editing-style variance; AC-P.12 validates the actual JSON-validity outcome.
- [ ] AC-1.7 — `diff -q skills/update-zskills/scripts/zskills-paths.sh .claude/skills/update-zskills/scripts/zskills-paths.sh` returns empty. Same for migrate-paths.sh.
- [ ] AC-1.8 — `bash tests/test-zskills-paths.sh` exits 0 (cases 10-12 pass).
- [ ] AC-1.9 — `bash tests/test-update-zskills-paths-migration.sh` exits 0 (extended cases 1+2 + new case 3 pass).
- [ ] AC-1.10 — `bash scripts/skill-content-hash.sh skills/update-zskills` output matches the `metadata.version` suffix in `skills/update-zskills/SKILL.md`.
- [ ] AC-1.11 — `diff -rq skills/update-zskills .claude/skills/update-zskills` returns empty.
- [ ] AC-1.12 — Full suite passes: `bash tests/run-all.sh` exits 0.

- [ ] AC-1.13 — Migrator idempotency (reviewer F7): running `bash skills/update-zskills/scripts/migrate-paths.sh` twice consecutively on the fully-migrated `.claude/zskills-config.json` produces no second diff. `cp` snapshots before/after each run; `diff` of the two post-run snapshots is empty. This locks AC-P.11.

- [ ] AC-1.14 — Standalone awk fixture passes (Round 2 Gap B — locks WI 1.7-bis): `bash tests/test-migrate-paths-awk.sh` exits 0. The driver iterates every directory under `tests/fixtures/migrate-paths-awk/`, runs the awk program from `migrate-paths.sh` against each `input.json` with the case-specific `plans` / `issues` / `reports` env vars, validates output is parseable JSON via `python3 -c 'import json,sys; json.load(sys.stdin)'`, and compares canonicalized output to `expected.json`. All 9 cases (a-i per WI 1.7-bis) pass. This AC closes Phase 1 — DO NOT advance to Phase 2 if AC-1.14 fails.

### Dependencies

None. Phase 1 is the foundation for Phases 2 and 3.

---

## Phase 2 — Writer + reader path swap across affected skills

### Goal

Swap `$ZSKILLS_AUDIT_DIR/<reports-pattern>` references to `$ZSKILLS_REPORTS_DIR/<reports-pattern>` across the three writer skills + four reader skills + dashboard collector. Per-skill metadata.version bump and mirror update. No file moves yet (Phase 3 does that) — at end of Phase 2 the writers reference the new env var, the readers look at the new env var, and the conformance/path-test results stay green.

### Work Items

- [ ] WI 2.1 — `/run-plan` writer swap. **17 verified hits** (DA-7: research undercounted at 5). Live enumeration as of plan draft (re-run `grep -rnE '\$ZSKILLS_AUDIT_DIR/plan-' skills/run-plan/` at implementation time — count may drift):

  | File | Line | Pattern | Action |
  |------|------|---------|--------|
  | `skills/run-plan/SKILL.md` | 8 | `$ZSKILLS_AUDIT_DIR/plan-{slug}.md` | SWAP → `$ZSKILLS_REPORTS_DIR/` |
  | `skills/run-plan/SKILL.md` | 1054 | "Mark phase as Timed out in `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`" | SWAP |
  | `skills/run-plan/SKILL.md` | 1973 | "PREPEND new phase sections after the H1 in `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`" | SWAP |
  | `skills/run-plan/SKILL.md` | 1999 | "Scan `$ZSKILLS_AUDIT_DIR/plan-*.md` files" | SWAP |
  | `skills/run-plan/SKILL.md` | 2199 | corresponding section in `$ZSKILLS_AUDIT_DIR/plan-{slug}.md` | SWAP |
  | `skills/run-plan/SKILL.md` | 2228 | "See $ZSKILLS_AUDIT_DIR/plan-{slug}.md for details" | SWAP |
  | `skills/run-plan/SKILL.md` | 2477 | "Plan report exists at `$ZSKILLS_AUDIT_DIR/plan-<slug>.md`" | SWAP |
  | `skills/run-plan/SKILL.md` | 2538 | "Report in `$ZSKILLS_AUDIT_DIR/plan-{slug}.md` as ..." | SWAP |
  | `skills/run-plan/modes/cherry-pick.md` | 16 | `ls $ZSKILLS_AUDIT_DIR/plan-{slug}.md` | SWAP |
  | `skills/run-plan/modes/cherry-pick.md` | 45 | "Report written to `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`" | SWAP |
  | `skills/run-plan/modes/cherry-pick.md` | 55 | "Report written to `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`" | SWAP |
  | `skills/run-plan/modes/cherry-pick.md` | 165 | "Update the plan report (`$ZSKILLS_AUDIT_DIR/plan-{slug}.md`)" | SWAP |
  | `skills/run-plan/modes/pr.md` | 182 | "Also regen `$ZSKILLS_AUDIT_DIR/plan-{slug}.md`" | SWAP |
  | `skills/run-plan/modes/pr.md` | 196 | `git add <plan-file> ["$ZSKILLS_AUDIT_DIR/plan-{slug}.md" "$ZSKILLS_AUDIT_DIR/PLAN_REPORT.md"]` | **PARTIAL SWAP** — `plan-{slug}.md` → REPORTS_DIR; `PLAN_REPORT.md` STAYS at AUDIT_DIR (per triage table — PLAN_REPORT.md is a roll-up index, not work-trail). Reviewer F10 caught this exact risk. |
  | `skills/run-plan/modes/pr.md` | 250 | "See `$ZSKILLS_AUDIT_DIR/plan-${PLAN_SLUG}.md`" | SWAP |
  | `skills/run-plan/references/failure-protocol.md` | 85 | "See $ZSKILLS_AUDIT_DIR/plan-{slug}.md" | SWAP |
  | `skills/run-plan/scripts/post-run-invariants.sh` | 127 | `REPORT_PATH="$ZSKILLS_AUDIT_DIR/plan-${PLAN_SLUG}.md"` | SWAP |

  **Per-hit triage** (per triage table in plan-wide Design & Constraints):
  - `plan-{slug}.md`, `plan-*.md`, `plan-<slug>.md` → SWAP to REPORTS_DIR
  - `PLAN_INDEX.md`, `PLAN_REPORT.md`, `briefing-*.md`, debug dumps → STAY at AUDIT_DIR

  Verify the swap via:
  ```bash
  grep -nE '\$ZSKILLS_AUDIT_DIR/plan-' skills/run-plan/ -r | wc -l   # expect 0
  grep -nE '\$ZSKILLS_REPORTS_DIR/plan-' skills/run-plan/ -r | wc -l # expect 17 (or live count)
  grep -nE '\$ZSKILLS_AUDIT_DIR/PLAN_(INDEX|REPORT)' skills/run-plan/ -r | wc -l  # expect ≥ 1 (PLAN_REPORT.md must remain at AUDIT_DIR)
  ```
  Then bump version:
  ```bash
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  HASH=$(bash scripts/skill-content-hash.sh skills/run-plan)
  bash scripts/frontmatter-set.sh skills/run-plan/SKILL.md metadata.version "$TODAY+$HASH"
  bash scripts/mirror-skill.sh run-plan
  ```

- [ ] WI 2.2 — `/verify-changes` writer swap. 15 hits in `skills/verify-changes/SKILL.md`. Swap `$ZSKILLS_AUDIT_DIR/verify-*` and `$ZSKILLS_AUDIT_DIR/verify-last-*` patterns to `$ZSKILLS_REPORTS_DIR/`. Per the triage table, `VERIFICATION_REPORT.md` (uppercase roll-up) stays in AUDIT_DIR — only the lowercase `verify-{name}.md` / `verify-last-{N}.md` work-trail files move. Verify:
  ```bash
  grep -nE '\$ZSKILLS_AUDIT_DIR/verify-' skills/verify-changes/SKILL.md
  ```
  Returns 0 after swap. Then bump + mirror.

- [ ] WI 2.3 — `/fix-issues` writer swap. 26 hits across `skills/fix-issues/SKILL.md`, `skills/fix-issues/modes/cherry-pick.md`, `skills/fix-issues/references/failure-protocol.md`. Swap ONLY the `SPRINT_REPORT.md` references — every other audit reference in these files (FIX_REPORT.md, tracker markers, debug dumps) STAYS in AUDIT_DIR.

  Specifically swap: `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` → `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md`. Verify:
  ```bash
  grep -nE '\$ZSKILLS_AUDIT_DIR/SPRINT_REPORT' skills/fix-issues/ -r
  ```
  Returns 0 after swap. Bump + mirror.

- [ ] WI 2.4 — `/briefing` reader swap. **`briefing.py` has a LOCAL-VARIABLE SHADOWING TRAP** (DA-3 verified, 5 hits): at lines 513, 572, 1310, 1440, 1677 the code does `reports_dir = paths['audit_dir']` or `reports_dir = read_zskills_paths(...)['audit_dir']` — the local var name `reports_dir` already holds what is semantically the AUDIT_DIR. Naive "swap reports_dir → reports_dir" is a no-op that LEAKS the audit semantics into the new name. Mandatory two-stage fix:

  **Stage A — RENAME the misleading local variable.** Across all 5 sites:
  ```python
  # Before:
  reports_dir = paths['audit_dir']           # MISLEADING — holds audit_dir
  # After:
  audit_dir = paths['audit_dir']             # variable name matches semantic content
  ```
  Update ALL downstream uses inside each function — likely the next 5-30 lines per site reference the local name. Use the function-scope rename pattern; do NOT do a global `s/reports_dir/audit_dir/g`.

  **Stage B — Per-site classification.** After the rename, audit each `audit_dir` use and decide per the triage table:
  - If the use is reading/writing `briefing-{date}.md` → KEEP `audit_dir` (semantically correct).
  - If the use is reading `plan-*.md`, `verify-*.md`, or `SPRINT_REPORT.md` → introduce a SEPARATE local `reports_dir = paths['reports_dir']` (a NEW key from `read_zskills_paths` — see Stage C) and swap the path constructor.

  Per-site verified call-site list (re-grep at impl time; line numbers may drift):
  | Line | Current text | Pattern accessed | Stage B disposition |
  |------|--------------|-------------------|---------------------|
  | 513 | `reports_dir = read_zskills_paths(main_path)['audit_dir']` | Plus surrounding `plan-*` / `verify-*` reads | RENAME local to `audit_dir`; ADD `reports_dir = paths['reports_dir']`; per-path-construction swap |
  | 572 | `reports_dir = paths['audit_dir']` | (re-read context: which file pattern) | RENAME; ADD; classify |
  | 1310 | `reports_dir = read_zskills_paths(main_path)['audit_dir']` | (re-read context) | RENAME; ADD; classify |
  | 1440 | `reports_dir = read_zskills_paths(main_path)['audit_dir']` | (re-read context) | RENAME; ADD; classify |
  | 1677 | `reports_dir = read_zskills_paths(main_path)['audit_dir']` | (re-read context) | RENAME; ADD; classify |

  **Stage C — Extend `read_zskills_paths()` helper.** Add a `reports_dir` key alongside `audit_dir`:
  ```python
  def read_zskills_paths(main_path):
      # ... existing logic for audit_dir/plans_dir/issues_dir ...
      output = cfg.get("output", {})
      reports_rel = output.get("reports_dir")  # absent → legacy fallback
      if reports_rel:
          reports_dir = (pathlib.Path(reports_rel) if pathlib.Path(reports_rel).is_absolute()
                         else main_path / reports_rel)
      else:
          reports_dir = main_path / ".zskills" / "audit"  # legacy fallback
      return {
          ..., 'audit_dir': ..., 'reports_dir': reports_dir,
      }
  ```

  Verify Python side after the three stages:
  ```bash
  grep -nE 'reports_dir|audit_dir' skills/briefing/scripts/briefing.py
  ```
  Hits should split sensibly: `audit_dir` for briefing-* / debug; `reports_dir` for plan-* / verify-* / SPRINT_REPORT.

  Also `skills/briefing/SKILL.md` reader hits (~10 prose mentions of `$ZSKILLS_AUDIT_DIR/plan-*` etc.) — swap per the file-pattern triage table.

  Bump `briefing` + mirror.

- [ ] WI 2.5 — `/fix-report` reader/writer swap. 14 hits in `skills/fix-report/SKILL.md`. `/fix-report` writes `FIX_REPORT.md` (stays AUDIT_DIR, roll-up index) and reads `SPRINT_REPORT.md` (swap to REPORTS_DIR). Per the triage table.

  Verify:
  ```bash
  grep -nE '\$ZSKILLS_AUDIT_DIR/SPRINT_REPORT' skills/fix-report/SKILL.md
  ```
  Returns 0 after swap; FIX_REPORT.md references unchanged.

  Bump + mirror.

- [ ] WI 2.6 — Dashboard collector. **`_resolve_paths()` helper at collect.py:240-253 has NO `reports_dir` key today (DA-4 verified)** — it returns `{plans_dir, issues_dir, audit_dir}`. Two-step:

  **Step 1 — Extend `_resolve_paths()`.** Read `output.reports_dir` from `cfg` (parallel to `plans_dir`/`issues_dir`), with legacy fallback to `.zskills/audit`:
  ```python
  reports_rel = output.get("reports_dir")
  if reports_rel:
      reports_dir = (pathlib.Path(reports_rel) if pathlib.Path(reports_rel).is_absolute()
                     else main_root / reports_rel)
  else:
      reports_dir = main_root / ".zskills" / "audit"  # legacy fallback
  return {
      "plans_dir": _resolve(plans_rel),
      "issues_dir": _resolve(issues_rel),
      "audit_dir": main_root / ".zskills" / "audit",
      "reports_dir": reports_dir,
  }
  ```

  **Step 2 — Per-call-site swap.** The call site at line ~579 reads `<audit_dir>/plan-{slug}.md`. Swap to `<reports_dir>/plan-{slug}.md`. Re-grep call sites and verify:
  ```bash
  grep -nE 'audit_dir|reports_dir' skills/zskills-dashboard/scripts/zskills_monitor/collect.py
  ```
  Each `[X]_dir` use must match the file pattern accessed (plan-*/verify-*/SPRINT → reports; debug/forensic → audit).

  **Version bump REQUIRED (reviewer F6).** `bash scripts/skill-content-hash.sh` recurses every regular file under the skill (excluding only SKILL.md/dotfiles/`__pycache__`/`node_modules` per the script's documented projection). Editing `collect.py` changes the hash — so `metadata.version` in `skills/zskills-dashboard/SKILL.md` MUST be bumped via the canonical recipe. Mirror via `bash scripts/mirror-skill.sh zskills-dashboard`.

- [ ] WI 2.7 — Negative-assertion prose updates — **DROPPED per reviewer F11/F12**.

  Re-reading the actual prose:
  - `skills/do/SKILL.md:925-929` says "MUST NOT write any report file under `$ZSKILLS_AUDIT_DIR` (e.g., the canonical `SPRINT_REPORT.md` / `PLAN_REPORT.md` artifacts owned by other skills)." Post-migration, `SPRINT_REPORT.md` moves to REPORTS_DIR; `PLAN_REPORT.md` stays at AUDIT_DIR. The "must not write under `$ZSKILLS_AUDIT_DIR`" prohibition remains TRUE (because `PLAN_REPORT.md` is still there). The example list is now mixed-location, but the asserted invariant ("no report file under audit dir") still holds. The negative assertion is structurally correct as-is.
  - `skills/investigate/SKILL.md:280-282` says "No `$ZSKILLS_AUDIT_DIR/investigate-*.md`." Since no `investigate-*.md` file exists in scope of this migration and the assertion is about FILES THIS SKILL DOESN'T WRITE, swapping env var names would actually weaken accuracy (the audit-dir prohibition is the correct one to assert for an investigate-* file that DOESN'T fit the work-trail pattern).

  **Net: leave both files unchanged.** No version bumps for `do` or `investigate`. AC-P.4 mirror check correspondingly drops these from the touched-skill list.

- [ ] WI 2.8 — Comment-only mentions in `skills/draft-plan/SKILL.md:80`, `skills/draft-tests/SKILL.md:94`, `skills/refine-plan/SKILL.md:91`. These name `$ZSKILLS_AUDIT_DIR` in a bash-comment alongside `$ZSKILLS_PLANS_DIR` in a worktree-export pattern. Per the triage table, those skills' output ISN'T a work-trail report — they're invoking sub-agents that may write to AUDIT_DIR for forensic exhaust. **Leave these as `$ZSKILLS_AUDIT_DIR` unchanged.** Document this in the plan as a deliberate non-edit.

  If implementer reading the file determines the comment ACTUALLY refers to a plan-trail file (e.g., "export so /run-plan can write plan-{slug}.md"), THEN swap. Read each line in context before deciding.

- [ ] WI 2.9 — Conformance test: `tests/test-skill-conformance.sh` extension to assert no `$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)` patterns appear in the swapped skills' source. Pattern-grep gate near line 2000-2010 (the existing skill-dir cleanliness area):
  ```bash
  echo "=== Reports-dir writer placement (issue #217) ==="
  for skill in run-plan verify-changes fix-issues; do
    leak=$(grep -rE '\$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)' "$REPO_ROOT/skills/$skill" || true)
    if [ -n "$leak" ]; then
      fail "[reports-dir-placement] $skill" "Found legacy '\$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)' references — must use \$ZSKILLS_REPORTS_DIR (issue #217). Hits:
$leak"
    else
      pass "[reports-dir-placement] $skill: no legacy AUDIT_DIR-for-reports references"
    fi
  done
  ```
  This locks the writer placement so a future regression is caught at CI.

- [ ] WI 2.10 — Per-skill commits (DA-14: do NOT batch multi-skill version bumps in one staging pass — the `block-stale-skill-version.sh` PreToolUse hook re-hashes against currently-staged content and will deny if intermediate stages drift). **One commit per skill** (so blame is useful AND each commit is self-consistent re: hash↔version pairing). Order:
  1. `refactor(run-plan): swap plan-* writes from $ZSKILLS_AUDIT_DIR to $ZSKILLS_REPORTS_DIR (#217)`
  2. `refactor(verify-changes): swap verify-* writes from $ZSKILLS_AUDIT_DIR to $ZSKILLS_REPORTS_DIR (#217)`
  3. `refactor(fix-issues): swap SPRINT_REPORT writes from $ZSKILLS_AUDIT_DIR to $ZSKILLS_REPORTS_DIR (#217)`
  4. `refactor(briefing): split audit_dir vs reports_dir reads; rename misleading local (#217)`
  5. `refactor(fix-report): swap SPRINT_REPORT reads to $ZSKILLS_REPORTS_DIR (#217)`
  6. `refactor(zskills-dashboard): extend _resolve_paths with reports_dir; swap collect.py:579 (#217)`
  7. `test(conformance): assert no $ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT) leaks (#217)`

  Each commit MUST include the skill's source edit + mirror + version-bump for that skill (and ONLY that skill). The version-bump is a per-commit invariant; staging two skills' bumps together risks the hook re-hashing against a partial state.

  **Failure mode — what the `block-stale-skill-version.sh` hook will reject (Round 2 Gap A):** the hook re-runs `scripts/skill-version-stage-check.sh` on every `git commit` Bash invocation (per `hooks/block-stale-skill-version.sh:125-129`). The stage-check iterates the staged-set (`git diff --cached --name-only`), groups files under `(skills|block-diagram)/<name>/`, and for each unique skill compares three values per `scripts/skill-version-stage-check.sh:78-92`:
  - `cur_hash` = `bash scripts/skill-content-hash.sh skills/<name>` (worktree projection)
  - `staged_hash` = suffix of staged `SKILL.md`'s `metadata.version` (or, if SKILL.md not staged, the on-disk version)
  - `head_hash` = suffix of HEAD's `SKILL.md`'s `metadata.version`

  Two failure modes (per the script's `## Failure modes` docstring lines 12-17):
  1. **Asymmetric (line 95):** `cur_hash != head_hash` AND `staged_ver == head_ver` → "content changed but staged metadata.version still <ver>". STOP message includes the literal recovery command: `bash scripts/frontmatter-set.sh <S>/SKILL.md metadata.version "$today+$hash"`.
  2. **Symmetric (line 107):** `cur_hash == head_hash` AND `staged_ver != head_ver` (non-empty) → "metadata.version bumped but content unchanged".

  **The specific batching trap WI 2.10 prevents:** if the implementer stages skill A's edits + version-bump AND skill B's edits WITHOUT bumping B's version (intending to bump B in a later commit), the hook fires asymmetric-mode against B at commit time — the staged-set includes both A and B, the per-skill loop visits B, sees B's worktree hash drifted from HEAD with no staged bump, denies. The serial per-skill-commit order in this WI is the structural fix: each commit's `git add` includes ONLY one skill's `<skill-source>/`, `.claude/skills/<skill>/`, and `SKILL.md` bump — so the stage-check loop sees exactly one skill and that skill is internally consistent.

  **Recovery if the hook denies during Phase 2:** read the deny envelope's `permissionDecisionReason` (rendered verbatim in tool-error output); it carries the STOP message including the exact `frontmatter-set.sh` command for each skill in `FAIL_LIST`. Run those commands, then re-stage ONLY the affected skill's bump, then re-issue `git commit`. Do NOT add unrelated skills to the same commit to "fix it up" — that re-introduces the batching trap.

- [ ] WI 2.11 — After all swaps, run the full suite per the canonical idiom; verify the new WI 2.9 conformance assertion passes. **Phase-2-vs-Phase-3 ordering note (reviewer F5):** the `.zskills-umbrella` end-state assertion (`git ls-files .zskills/ | wc -l == 0`) is NOT YET added at this point — that assertion is added in WI 3.6, AFTER the files are moved in WI 3.3-3.4. At end of Phase 2 the full suite should pass because the umbrella-cleanliness assertion does not yet exist; the WI 2.9 writer-placement assertion does exist and passes. **Note: the actual `.zskills/audit/plan-*.md` files still exist on disk at Phase 2 end — Phase 3 moves them.** This is fine: the writers reference the new env var, but the existing files at the legacy path still resolve correctly through tools that read them by the legacy path.

### Design & Constraints

- **Per-hit triage discipline.** The triage table in plan-wide Design & Constraints is the authoritative classifier. Implementer MUST read each grep hit in context before swapping — don't blind `sed -i` replace `ZSKILLS_AUDIT_DIR` to `ZSKILLS_REPORTS_DIR` across files; some references must stay AUDIT_DIR.
- **Verifier instruction.** The verifier subagent should re-grep `$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)` across the touched skill trees and confirm 0 hits; AND should re-grep `$ZSKILLS_AUDIT_DIR/(briefing-|FIX_REPORT|PLAN_INDEX|work-on-plans|new-blocks-|NEW_BLOCKS_REPORT|VERIFICATION_REPORT|PLAN_REPORT)` and confirm hits remain (those legitimately stay).
- **briefing.py is the most subtle.** The Python script has both audit_dir and reports_dir consumers; the implementer should expose both via the helper, not collapse them. Mirror byte-equality applies to Python files too (`bash scripts/mirror-skill.sh briefing` handles it).
- **Negative-assertion prose stays accurate.** The phrasing change in WI 2.7 must preserve the "MUST NOT" semantics — the goal is "no work-trail file written by this skill," not "no write to either env-var."
- **Per-skill version bumps are mandatory.** Each skill whose source files change in Phase 2 (run-plan, verify-changes, fix-issues, briefing, fix-report, do, investigate) gets its `metadata.version` bumped. `update-zskills` was bumped in Phase 1 — if no source changes in Phase 2, no second bump needed (but Phase 3 may rebump if mirror drifts during landing).

### Acceptance Criteria

- [ ] AC-2.1 — `grep -rnE '\$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)' skills/ block-diagram/` returns 0 hits (across all source skills — the writer swap is complete).
- [ ] AC-2.2 — `grep -rnE '\$ZSKILLS_AUDIT_DIR/(plan-|verify-|SPRINT_REPORT)' .claude/skills/` returns 0 hits (mirrors swapped too).
- [ ] AC-2.3 — `grep -rnE '\$ZSKILLS_REPORTS_DIR/(plan-|verify-|SPRINT_REPORT)' skills/run-plan skills/verify-changes skills/fix-issues` returns ≥ the live counts captured in the per-skill enumeration tables (DA-7: run-plan = 17, verify-changes = 13, fix-issues = 18; floor `≥ 45` combined). Implementer re-greps source before swapping; AC floor matches live count at impl time.
- [ ] AC-2.4 — Briefing reader: `grep -E 'reports_dir' skills/briefing/scripts/briefing.py` returns ≥ 5 hits (the helper now exposes reports_dir; per-site reads use it for plan-*/verify-*/SPRINT). `grep -E 'audit_dir' skills/briefing/scripts/briefing.py` still returns ≥ 3 hits (briefing-* writes still hit audit_dir).
- [ ] AC-2.5 — Dashboard collector: `grep -nE 'reports_dir' skills/zskills-dashboard/scripts/zskills_monitor/collect.py` returns ≥ 1 hit at line ~579.
- [ ] AC-2.6 — Conformance test extension at `tests/test-skill-conformance.sh` runs and passes: `bash tests/test-skill-conformance.sh 2>&1 | grep -cE 'reports-dir-placement.*: no legacy'` returns ≥ 3 (one per touched writer skill).
- [ ] AC-2.7 — Audit-dir references for non-report patterns STAY: `grep -rE '\$ZSKILLS_AUDIT_DIR/(briefing-|FIX_REPORT|PLAN_INDEX|new-blocks-|work-on-plans|VERIFICATION_REPORT|PLAN_REPORT|NEW_BLOCKS_REPORT)' skills/ | wc -l` returns ≥ 10 (legitimate audit references preserved; not over-swapped).
- [ ] AC-2.8 — Per-skill mirror byte-equality: for each of `run-plan`, `verify-changes`, `fix-issues`, `briefing`, `fix-report`, `zskills-dashboard`: `diff -rq --exclude=__pycache__ --exclude='*.pyc' skills/<skill> .claude/skills/<skill>` returns empty. (`do` and `investigate` dropped per WI 2.7 F11/F12; `__pycache__` excluded per DA-2.)
- [ ] AC-2.9 — Per-skill version-bump current: for each touched skill, `bash scripts/skill-content-hash.sh skills/<skill>` matches the `metadata.version` suffix.
- [ ] AC-2.10 — Full suite: `bash tests/run-all.sh` exits 0. `bash tests/test-skill-conformance.sh` exits 0.

- [ ] AC-2.11 — Per-skill commit hash↔version pairing holds AT STAGING TIME (Round 2 Gap A — exercises `block-stale-skill-version.sh`). Run the stage-check script directly against each Phase 2 commit's staged-set, BEFORE the commit, asserting clean (rc=0). The hook will fire on the `git commit` itself; this AC pre-flights the same check so an implementer who hits a deny has explicit "expected clean — investigate the FAIL_LIST" guidance. Verification (run once per Phase 2 commit, between `git add <skill>` and `git commit`):
  ```bash
  CLAUDE_PROJECT_DIR="$(git rev-parse --show-toplevel)" \
    bash scripts/skill-version-stage-check.sh
  echo "stage-check rc=$?"
  ```
  Expect `rc=0` (clean) on each of the 7 commits in WI 2.10. If `rc=1`, the printed STOP message (stderr) enumerates the asymmetric/symmetric drift per skill and includes the literal recovery command. Per Round 2 Gap A failure-mode callout in WI 2.10: the implementer recovers by running the recovery command, re-staging ONLY the affected skill, and re-running stage-check until rc=0. Commits 1-6 each iterate exactly one skill in the stage-check loop (the `SKILLS_TO_CHECK` set per `scripts/skill-version-stage-check.sh:44-48`); commit 7 (conformance test) iterates ZERO skills (the staged file lives under `tests/`, not `skills/<name>/`), so stage-check is a trivial no-op pass.

### Dependencies

Phase 1 must be complete and merged into the working branch (so `$ZSKILLS_REPORTS_DIR` resolves correctly in test invocations of the swapped writers).

---

## Phase 3 — Migration commit + conformance + final version bumps

### Goal

Move the 44 force-tracked work-trail files (`git mv`) and untrack the 13 remaining files (`git rm --cached`) in a single atomic commit. Add the end-state invariant assertion (`git ls-files .zskills/ | wc -l == 0`) to `tests/test-skill-conformance.sh`. Catch any residual skill-version drift from verifier-polish commits in Phase 2.

### Work Items

- [ ] WI 3.0 — **Pause any active `/fix-issues` cron BEFORE WI 3.1** (DA-8 hard requirement). Per the Hot-Path section above, a live cron firing during WI 3.3 produces an invisible orphan after PR merge. Stop the cron:
  ```bash
  # Identify the active fix-issues schedule (if any).
  /schedule list 2>&1 | grep -iE 'fix-issues' || echo "no fix-issues schedule active"
  # If present, suspend it. Exact command depends on the schedule manager state at impl time.
  ```
  Document the pre-stop schedule state; resume AFTER PR merge in WI 3.11. If `/schedule list` shows no `fix-issues` schedule, record "no schedule active — skipping pause" and proceed.

- [ ] WI 3.1 — Pre-flight inventory. **Compute counts dynamically (DA-10)** — point-in-time numbers (38/5/1/7/6/44/13/57) WILL drift between plan-draft and implementation as `/run-plan` writes new `plan-*.md` artifacts. Capture LIVE numbers into shell vars and use them throughout Phase 3:
  ```bash
  N_PLAN=$(git ls-files .zskills/audit/plan-*.md 2>/dev/null | wc -l)
  N_VERIFY=$(git ls-files .zskills/audit/verify-*.md 2>/dev/null | wc -l)
  N_SPRINT=$(git ls-files .zskills/audit/SPRINT_REPORT.md 2>/dev/null | wc -l)
  N_AUDIT_OTHER=$(git ls-files .zskills/audit/ 2>/dev/null | grep -vE '^.zskills/audit/(plan-|verify-|SPRINT_REPORT)' | wc -l)
  N_TRACKING=$(git ls-files .zskills/tracking/ 2>/dev/null | wc -l)
  N_TOTAL=$(git ls-files .zskills/ 2>/dev/null | wc -l)
  N_MOVE=$((N_PLAN + N_VERIFY + N_SPRINT))
  N_UNTRACK=$((N_AUDIT_OTHER + N_TRACKING))
  echo "MOVE=$N_MOVE  UNTRACK=$N_UNTRACK  TOTAL=$N_TOTAL"
  echo "Expected at plan-draft: MOVE=44 UNTRACK=13 TOTAL=57"
  ```
  Compare. If `N_TOTAL != N_MOVE + N_UNTRACK`, STOP — there's a category drift not captured above. If MOVE/UNTRACK/TOTAL differ from the draft expectations by more than +5 (likely due to new plan-*.md / verify-*.md writes since draft), CONTINUE but explicitly log the delta in the migration commit message.

  Also: protect untracked files per CLAUDE.md "Protect untracked files" rule:
  ```bash
  git status -s | grep '^??' | head -20
  ```
  If any untracked files exist in the worktree, inventory them and stash with `-u` if needed.

- [ ] WI 3.2 — Create destination: `mkdir -p docs/reports/` (no `.gitignore` exception needed; docs/ is outside `.zskills/` umbrella). Verify:
  ```bash
  [ -d docs/reports ] && echo OK || echo MISSING
  ```

- [ ] WI 3.3 — `git mv` all `N_MOVE` files (live count from WI 3.1; was 44 at draft). Use a loop to keep the diff inspectable:
  ```bash
  for f in $(git ls-files .zskills/audit/plan-*.md \
                          .zskills/audit/verify-*.md \
                          .zskills/audit/SPRINT_REPORT.md); do
    base=$(basename "$f")
    git mv "$f" "docs/reports/$base" && echo "mv: $f -> docs/reports/$base"
  done
  ```
  Verify post-move:
  ```bash
  git ls-files .zskills/audit/plan-*.md .zskills/audit/verify-*.md .zskills/audit/SPRINT_REPORT.md | wc -l  # expect 0
  git ls-files docs/reports/ | wc -l  # expect 44
  git status --porcelain | grep -E '^R' | wc -l  # expect 44 renames
  ```

- [ ] WI 3.4 — `git rm --cached` the audit one-offs + stray tracking markers. **Use the live inventory from WI 3.1 (DA-10) — do not hardcode filenames** in case new ones accumulate between draft and implementation. At draft time the set was 13 files (7 audit + 6 tracking); the canonical list:
  ```bash
  # Untrack any audit/* that isn't plan-/verify-/SPRINT_REPORT (i.e., the leftover audit one-offs).
  git ls-files .zskills/audit/ \
    | grep -vE '^\.zskills/audit/(plan-|verify-|SPRINT_REPORT)' \
    | xargs -r git rm --cached
  # Untrack everything under .zskills/tracking/ (stray markers per WI 3.1 inventory).
  git ls-files .zskills/tracking/ | xargs -r git rm --cached
  # If WI 3.1 surfaced files under other .zskills/<subtree>/ paths, enumerate and untrack.
  ```
  Implementer SHOULD print the exact list of files-to-be-untracked BEFORE running the `xargs git rm --cached` for human inspection (e.g., dry-run `echo` first), then run for real. Sample expected at draft time (7 + 6 = 13):
  ```
  .zskills/audit/SKILL_VERSION_PRETOOLUSE_HOOK-followups.md
  .zskills/audit/VERIFIER_AGENT_FIX-anthropic-issue-draft.md
  .zskills/audit/baseline-pre-restructure.md
  .zskills/audit/migration-warnings.md
  .zskills/audit/post-restructure-verification.md
  .zskills/audit/post-restructure-verification-plan.md
  .zskills/audit/restructure-readiness.md
  .zskills/tracking/run-plan.dashboard-tabs-and-rename/fulfilled.run-plan.dashboard-tabs-and-rename
  .zskills/tracking/run-plan.dashboard-tabs-and-rename/requires.land-pr.dashboard-tabs-and-rename
  .zskills/tracking/run-plan.dashboard-tabs-and-rename/requires.verify-changes.dashboard-tabs-and-rename
  .zskills/tracking/run-plan.dashboard-tabs-and-rename/step.run-plan.dashboard-tabs-and-rename.implement
  .zskills/tracking/run-plan.dashboard-tabs-and-rename/step.run-plan.dashboard-tabs-and-rename.report
  .zskills/tracking/run-plan.dashboard-tabs-and-rename/step.run-plan.dashboard-tabs-and-rename.verify
  ```
  Verify on-disk persistence + git-ignored status:
  ```bash
  for f in .zskills/audit/migration-warnings.md \
           .zskills/tracking/run-plan.dashboard-tabs-and-rename/fulfilled.run-plan.dashboard-tabs-and-rename; do
    [ -f "$f" ] && echo "ON-DISK: $f"
    git check-ignore "$f" >/dev/null 2>&1 && echo "IGNORED: $f"
  done
  ```
  Expect ON-DISK + IGNORED for each.

- [ ] WI 3.5 — Append migration mappings to `.pre-paths-migration` audit trail. Per locked decision 10, reuse the existing file. **DA-15 + reviewer F3 fix: do NOT filter `awk '$1 == "R100"'`** — partial-similarity renames (e.g., 0-byte `verify-last-*.md` files, or files git decides are R85/R90 rather than R100) would be dropped. Use any-rename match OR iterate the move list directly:
  ```bash
  TODAY=$(TZ=America/New_York date +%Y-%m-%d)
  {
    echo ""
    echo "# === reports_dir migration (#217, $TODAY) ==="
    # Match ANY rename (R000-R100) — the count-floor in AC-P.9 catches under-detection.
    git diff --cached --name-status --find-renames=10% | awk '$1 ~ /^R/ {print $2"\t"$3}'
  } >> .pre-paths-migration
  git add .pre-paths-migration
  ```
  Verify against the dynamic N_MOVE captured in WI 3.1:
  ```bash
  tail -200 .pre-paths-migration | grep -cE '\.zskills/audit/(plan-|verify-|SPRINT_REPORT)'
  ```
  Returns ≥ `$N_MOVE` (the live count from WI 3.1). If the count is LESS than N_MOVE, git did not detect some moves as renames — fall back to iterating the move list directly:
  ```bash
  for src in $(git ls-files .zskills/audit/plan-*.md .zskills/audit/verify-*.md .zskills/audit/SPRINT_REPORT.md); do
    echo "$src	docs/reports/$(basename "$src")"
  done >> .pre-paths-migration
  ```
  This is the deterministic fallback when `--find-renames` underdetects.

- [ ] WI 3.6 — Add the end-state conformance assertion in `tests/test-skill-conformance.sh`. Place near line 2000 (the skill-dir cleanliness block) since it's a similar git-ls-files cleanliness check. **DA-11 allow-list pattern (escape hatch for future force-tracked schema/lock files):**
  ```bash
  echo ""
  echo "=== .zskills/ umbrella cleanliness (issue #217) ==="
  # Allow-list: empty today, but exists so future legitimate force-adds (e.g., a
  # zskills-versions.lock file) can be added by editing the file rather than
  # editing this assertion. Format: one path per line, # for comments.
  ALLOWLIST="$REPO_ROOT/tests/zskills-tracked-allowlist.txt"
  if [ -f "$ALLOWLIST" ]; then
    allowed=$(grep -vE '^[[:space:]]*(#|$)' "$ALLOWLIST" | sort -u)
  else
    allowed=""
  fi
  tracked=$(git -C "$REPO_ROOT" ls-files -- ".zskills/" | sort -u)
  if [ -n "$allowed" ]; then
    leaked=$(comm -23 <(echo "$tracked") <(echo "$allowed"))
  else
    leaked="$tracked"
  fi
  leaked_count=$(echo "$leaked" | grep -c . || true)
  if [ "$leaked_count" -eq 0 ]; then
    pass "[.zskills-umbrella] no force-tracked files under .zskills/ outside allow-list (issue #217)"
  else
    fail "[.zskills-umbrella] $leaked_count force-tracked files under .zskills/ outside allow-list (must be 0; issue #217). First 10:
$(echo "$leaked" | head -10)"
  fi
  ```
  Also create `tests/zskills-tracked-allowlist.txt` with a comment-only body explaining the convention (commit as part of the migration; AC-P.1 expects empty allow-list AT MIGRATION TIME):
  ```
  # tests/zskills-tracked-allowlist.txt — paths under .zskills/ that may
  # legitimately be force-tracked despite the umbrella .gitignore.
  # Format: one path per line. Lines starting with # are comments.
  # AT MIGRATION TIME (issue #217): this file is empty by design — no
  # exemptions. Future legitimate force-adds (e.g., a zskills-versions.lock
  # schema file) add entries here.
  ```
  Verify:
  ```bash
  bash tests/test-skill-conformance.sh 2>&1 | grep -E '\.zskills-umbrella'
  ```
  Returns the pass message.

- [ ] WI 3.7 — Verifier-polish rebump for any skill whose hash drifted in Phase 2 (per the canonical recipe from FIX_ISSUES_SYNC_HARDENING.md Phase 5). `do` and `investigate` dropped from list per WI 2.7 (F11/F12: prose unchanged):
  ```bash
  for s in run-plan verify-changes fix-issues briefing fix-report update-zskills zskills-dashboard; do
    HASH_NOW=$(bash scripts/skill-content-hash.sh skills/$s)
    VER_NOW=$(bash scripts/frontmatter-get.sh skills/$s/SKILL.md metadata.version | sed 's/.*+//')
    if [ "$HASH_NOW" != "$VER_NOW" ]; then
      TODAY=$(TZ=America/New_York date +%Y.%m.%d)
      bash scripts/frontmatter-set.sh skills/$s/SKILL.md metadata.version "$TODAY+$HASH_NOW"
      bash scripts/mirror-skill.sh $s
      git add skills/$s/SKILL.md .claude/skills/$s/SKILL.md
      echo "rebumped $s"
    fi
  done
  ```
  Either a single rebump commit at the end, or fold into the migration commit if hash drift is found before WI 3.8.

- [ ] WI 3.8 — Commit the migration. Single commit:
  ```
  feat(reports): migrate plan/verify/SPRINT work-trail to docs/reports/, untrack residual audit one-offs (#217)

  - 44 git mv: .zskills/audit/{plan-*,verify-*,SPRINT_REPORT}.md -> docs/reports/
  - 13 git rm --cached: 7 audit one-offs + 6 stray tracking markers (umbrella .gitignore handles them)
  - tests/test-skill-conformance.sh: new .zskills-umbrella assertion locking git ls-files .zskills/ == 0
  - .pre-paths-migration: appended migration trailer per locked-decision-10

  End state: git ls-files .zskills/ | wc -l == 0. .zskills/ is now a uniform gitignored umbrella;
  work-trail reports live at docs/reports/, parallel with docs/plans/ and docs/issues/.

  Closes #217.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  ```
  **Important:** the `Closes #217` directive is intentional here — this commit IS the one that should close #217 at merge time. Do NOT include any other auto-close directives (AC-P.10).

- [ ] WI 3.9 — Run the full suite per canonical idiom. Verify all assertions pass, including the new `.zskills-umbrella` conformance check:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  echo "exit: $?"
  grep -E 'FAIL|\.zskills-umbrella' "$TEST_OUT/.test-results.txt"
  ```
  Expect exit 0 and only PASS lines for `.zskills-umbrella`.

- [ ] WI 3.10 — Verify frozen cross-refs self-heal **EXCLUDING pre-existing dead refs** (DA-1: `reports/plan-canary-5.md` and `reports/plan-foo.md` referenced in frozen plans but NEVER existed in `.zskills/audit/`, so they cannot be moved to `docs/reports/`). AC-P.6 verification (move-list-scoped):
  ```bash
  # Build the set of basenames actually in the move list.
  moved=$(git log -1 --format=%H --diff-filter=R -- docs/reports/ \
          | xargs -I{} git diff-tree --no-commit-id --name-status -r {} \
          | awk '$1 ~ /^R/ && $3 ~ /^docs\/reports\// {print $3}' \
          | xargs -n1 basename | sort -u)
  broken_in_move_set=0
  pre_existing_dead=0
  for ref in $(grep -hoE 'reports/plan-[a-z0-9-]+\.md' docs/plans/*.md | sort -u); do
    base=$(basename "$ref")
    if echo "$moved" | grep -qx "$base"; then
      if [ -f "docs/$ref" ]; then
        echo "OK: $ref"
      else
        echo "BROKEN-IN-MOVE-SET: $ref"
        broken_in_move_set=$((broken_in_move_set+1))
      fi
    else
      echo "PRE-EXISTING-DEAD (excluded): $ref"
      pre_existing_dead=$((pre_existing_dead+1))
    fi
  done | tee /tmp/xref-check.txt
  echo "broken_in_move_set=$broken_in_move_set"
  echo "pre_existing_dead=$pre_existing_dead"
  ```
  Expect `broken_in_move_set=0`. Pre-existing-dead refs are documented (currently 2: `plan-canary-5.md`, `plan-foo.md`) and intentionally NOT rewritten per locked decision 7.

- [ ] WI 3.11 — Dispatch `/land-pr` for PR landing. Per CLAUDE.md "Git Rules" and PR #166 conformance lock, dispatch `/land-pr` via the Skill tool — DO NOT call `gh pr create` or `gh pr merge --auto` directly.

  PR title: `feat: reports_dir — migrate work-trail to docs/reports, drive .zskills/ to zero force-tracked (#217)`.

  PR body should reference: this plan file (`docs/plans/REPORTS_DIR_MIGRATION.md`), the 3 phases + commit hashes, the end-state invariant, the umbrella gitignore preservation, and the `Closes #217` directive (NO other `Close[sd]?|Fixe[sd]?|Resolve[sd]?` directives per AC-P.10).

  `/land-pr` handles rebase, PR creation, CI monitoring, fix-cycle agent dispatch on CI failure, and auto-merge handling. User's `auto` arg (or its absence) governs the merge gate — this plan's drafter does NOT pre-decide that.

- [ ] WI 3.12 — Resume the `/fix-issues` cron (if paused in WI 3.0) AFTER PR merge:
  ```bash
  /schedule list 2>&1 | grep -iE 'fix-issues' || echo "no fix-issues schedule present"
  # If it was suspended in WI 3.0, restart it now.
  ```
  Confirm the next cron fire writes to the NEW `$ZSKILLS_REPORTS_DIR/SPRINT_REPORT.md` path (not the legacy audit path).

### Design & Constraints

- **One atomic commit for the 57-file disposition** — keeps the diff inspectable, the squash-merge clean, and the `.zskills/` umbrella invariant flips in a single step. Phase 2's writer-swap commits are separate (per-skill blame) and land in the same PR.
- **`.pre-paths-migration` reuse, not replacement.** `migrate-paths.sh` historically appends to this file; the new migration follows the same idiom. A separate `.pre-reports-migration` file would fragment the migration audit trail and break the script's idempotency assumption.
- **Conformance assertion placement.** The new `.zskills/ umbrella cleanliness` block goes near the existing skill-dir cleanliness checks (line ~2000) — same conceptual class (git-tracked-content invariant). Don't place it before `## Propagation-discipline prose rules` (line 1983) — that's a separate concern.
- **Hot-path SPRINT_REPORT.md mitigation.** The implementer should pause cron `/fix-issues` (if active) immediately before WI 3.3 — not strictly required (the migration is atomic and the file is append-only), but a courtesy that avoids one trailing legacy-path write during the PR-merge window. The user can decide.
- **Verifier-polish loop closure.** WI 3.7 catches the case where the verifier subagent committed a polish patch atop a Phase-2 per-skill version bump and left the hash drifted. Standard pattern from FIX_ISSUES_SYNC_HARDENING.md Phase 5; ship a single rebump commit if needed.
- **PR body discipline.** Per CLAUDE.md `## Constructing commits` AND the memory anchor `feedback_pr_closes_keyword_per_issue.md`: GitHub auto-closes from BOTH PR body and commit messages at squash-merge. `Closes #217` is the ONE directive intended for this PR; reference any other GH issues by bare `#NNN`. AC-P.10 enforces this.

### Acceptance Criteria

- [ ] AC-3.1 — `git ls-files .zskills/ | wc -l` returns `0` after the migration commit (allow-list is empty at this PR — see WI 3.6).
- [ ] AC-3.2 — `git ls-files docs/reports/ | wc -l` returns ≥ `$N_MOVE` (live count from WI 3.1; was 44 at draft time) after the migration commit.
- [ ] AC-3.3 — All 7 audit one-offs + 6 tracking markers remain ON DISK at their original paths under `.zskills/` (verified per-file). `git check-ignore` confirms each is now ignored.
- [ ] AC-3.4 — `tests/test-skill-conformance.sh` extended with `.zskills-umbrella` block; passes. Verification: `bash tests/test-skill-conformance.sh 2>&1 | grep -E '\.zskills-umbrella.*\[pass\]|\.zskills-umbrella' | grep -v fail | wc -l` ≥ 1.
- [ ] AC-3.5 — Full suite passes: `bash tests/run-all.sh` exits 0; `bash tests/test-skill-conformance.sh` exits 0; `bash tests/test-zskills-paths.sh` exits 0; `bash tests/test-update-zskills-paths-migration.sh` exits 0.
- [ ] AC-3.6 — Frozen cross-refs self-heal: `bash -c 'for f in $(grep -hoE "reports/plan-[a-z0-9-]+\.md" docs/plans/*.md | sort -u); do [ -f "docs/$f" ] && echo OK || echo BROKEN; done' | grep -c BROKEN` returns 0.
- [ ] AC-3.7 — `.pre-paths-migration` has the new trailer block: `grep -c '# === reports_dir migration (#217' .pre-paths-migration` returns 1; `tail -50 .pre-paths-migration | grep -cE '\.zskills/audit/(plan-|verify-|SPRINT_REPORT)'` returns ≥ 44.
- [ ] AC-3.8 — All touched skills have current `metadata.version` (verifier-polish rebump catch-net ran): for each of `run-plan verify-changes fix-issues briefing fix-report update-zskills zskills-dashboard`: `bash scripts/skill-content-hash.sh skills/<s>` matches `metadata.version` suffix.
- [ ] AC-3.9 — All mirrors byte-identical: for each touched skill, `diff -rq --exclude=__pycache__ --exclude='*.pyc' skills/<s> .claude/skills/<s>` returns empty.
- [ ] AC-3.10 — PR landing dispatched via `/land-pr` (not direct `gh pr create`/`merge`). PR body contains exactly ONE auto-close directive (`Closes #217`); AC-P.10 grep returns 0.
- [ ] AC-3.11 — Plan-level ACs (AC-P.1 through AC-P.10) all pass after this phase lands.

### Dependencies

Phases 1 and 2 must be complete on the same feature branch. The migration commit (WI 3.8) depends on Phase 2's writer-swap commits because the post-migration state has the writer pointing at the new env var AND the files at the new location — both must land in the same PR.

---

## Plan Quality

**Drafting process:** /draft-plan with N rounds of adversarial review (in progress; this is Round 1 refinement)

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 | 14 issues (2C/7M/5m) | 15 issues (6C/6M/3m) | 29/29 (27 fixed, 2 justified) |
| 2 | 0 new issues | 0 new issues | 2 prior-round gaps closed |

### Justified-not-fixed (Round 1)

- **F11/F12 — `do`/`investigate` negative-assertion prose (MINOR/MINOR):** verification showed the existing assertion ("MUST NOT write any report file under `$ZSKILLS_AUDIT_DIR`") remains structurally correct post-migration because `PLAN_REPORT.md` still lives at AUDIT_DIR. Editing it would be scope creep. WI 2.7 dropped; AC-P.4 / AC-2.8 / AC-3.9 mirror lists pruned correspondingly.

### Round 1 verification log (key claims)

- DA-3 verified: 5 sites in `briefing.py` use `reports_dir = paths['audit_dir']` (lines 513, 572, 1310, 1440, 1677). WI 2.4 rewritten with three-stage rename+classify+helper-extend plan.
- DA-4 verified: `_resolve_paths()` at collect.py:240-253 returns only `{plans_dir, issues_dir, audit_dir}`. WI 2.6 mandates helper extension.
- DA-5 verified: awk at migrate-paths.sh:820-821 emits unconditional `","` after injected keys. WI 1.6 part d rewritten with explicit trailing-comma management + d-bis pre-pass.
- DA-7 verified: `grep -rnE '\$ZSKILLS_AUDIT_DIR/plan-' skills/run-plan/` returns 17 hits (research said 5). WI 2.1 rewritten with full enumeration table.
- DA-12 verified: 13 existing cases in `test-update-zskills-paths-migration.sh` (cases 1-13). WI 1.9 rewritten with per-case classification table.
- DA-1 verified: `reports/plan-canary-5.md` + `reports/plan-foo.md` are pre-existing dead refs. AC-P.6 + WI 3.10 reworked to scope check to move-list and explicitly exclude pre-existing dead.
- Reviewer F2 verified: `grep -E` does NOT accept PCRE lookahead — confirmed via `echo "..." | grep -ciE '...(?!...)...'` errored. AC-P.10 rewritten to extract-then-filter form.
- Reviewer F6 verified: `bash scripts/skill-content-hash.sh skills/zskills-dashboard` recurses into scripts/ (per the script's documented projection §1.3). WI 2.6 mandates version bump.
- F1 verified: 6 stray tracking markers under `.zskills/tracking/run-plan.dashboard-tabs-and-rename/` (research said 0 there). Overview now reconciles 51→57 explicitly.
- DA-2 verified: `__pycache__/*.pyc` differ between mirrors. All `diff -rq` ACs amended with `--exclude=__pycache__ --exclude='*.pyc'`.

### Outstanding gaps / risks (drafter notes)

- ~~The `block-stale-skill-version.sh` hook on multi-skill commits has not been directly exercised under the Phase 2 commit pattern.~~ **Closed in Round 2 (Gap A):** WI 2.10 now carries a Failure-mode callout enumerating the exact asymmetric/symmetric drift modes from `scripts/skill-version-stage-check.sh:78-92, 95, 107`, with the recovery flow (read STOP message → run printed `frontmatter-set.sh` command → re-stage single skill → re-commit). AC-2.11 pre-flights the stage-check on each of the 7 per-skill commits to surface drift before the hook fires.
- ~~The 3-tuple awk extension in WI 1.6 part d/d-bis is the highest-risk change in the plan.~~ **Closed in Round 2 (Gap B):** WI 1.7-bis adds the standalone fixture directory `tests/fixtures/migrate-paths-awk/` (9 cases a-i covering no-output, expanded `{}`, 1-of-3 / 2-of-3 / 3-of-3 idempotent + comma-state edge cases), `tests/test-migrate-paths-awk.sh` driver with python3 JSON validation, and AC-1.14 ties Phase 1 closure to the fixture passing.
- Counts (38/5/1/7/6) are point-in-time. WI 3.1 now computes dynamically; AC-P.9 uses live count via `$N_MOVE`. Drift up to ~+5 expected during normal `/run-plan` activity; larger drift means STOP-and-resync per WI 3.1.
