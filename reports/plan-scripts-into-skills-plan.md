# Plan Report — Move skill-owned scripts into the skills that use them

## Phase — 4 /update-zskills install flow rewrite + stale-Tier-1 migration [UNFINALIZED]

**Plan:** plans/SCRIPTS_INTO_SKILLS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-scripts-into-skills-plan
**Branch:** feat/scripts-into-skills-plan
**Commits:** 18404ae (impl + new test + migration helper), 3b73e87 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 4.1 | Step D rewrite — drop Tier-1 enumerations, point readers to script-ownership.md | Done | 18404ae |
| 4.2 | references/tier1-shipped-hashes.txt generated via 2-pass form (literal + git ls-tree); 26 unique 40-char hex SHAs; --verify 2>/dev/null suppresses merge-commit literal-path stdout pollution | Done | 18404ae |
| 4.3 | Commit-cohabitation check implemented as case 6c | Done | 18404ae |
| 4.4 | Step D.5 stale-Tier-1 migration: command -v git pre-flight (DA-8), 14-entry STALE_LIST, CRLF-normalizing hash, MIGRATED/KEPT prompts, per-file defer marker | Done | 18404ae |
| 4.4b | port_script strip block + this-repo config update | Done | 18404ae |
| 4.5 | No bare scripts/statusline.sh in SKILL.md (only $PORTABLE/.claude/skills/.../) | Verified | (passive) |
| 4.6 | No scripts/briefing.* in SKILL.md (only .claude/skills/briefing/scripts/) | Verified | (passive) |
| 4.7 | Mirror parity for update-zskills | Done | 18404ae |
| 4.8 | tests/test-update-zskills-migration.sh (12 cases incl. case 6c uncommitted-in-worktree branch) | Done | 18404ae |
| 4.9 | Test registered in tests/run-all.sh alphabetically | Done | 18404ae |
| 4.10 | bash tests/run-all.sh exits 0 (943/943) | Done | 18404ae |

### Verification

- Test suite: PASSED (943/943, +12 from Phase 3b's 931 baseline)
- All 16 acceptance criteria verified by independent verification agent
- Migration sanity scenarios independently re-verified by verifier:
  - Known-hash blob → MIGRATED (matched, removed)
  - User-modified blob → KEPT (preserved, marker created)
  - CRLF fixture → cross-platform parity (`tr -d '\r' | git hash-object --stdin`)
- Step D.5 audit: command -v git pre-flight precedes STALE_LIST; no eval, no jq, no error-suppression on verifiable ops

### PLAN-TEXT-DRIFT findings

3 tokens flagged by both implementer and verifier (independently re-confirmed):
1. WI 4.1 closing-note example list contradicted AC2's zero-match grep. Resolved by keeping intent (script-ownership.md pointer), dropping example list. Only valid resolution.
2. WI 4.2 `git rev-parse` recipe needed `--verify ... 2>/dev/null` to suppress merge-commit literal-path stdout pollution. Sensible scope distinction: DA-3 rule was about wildcard-failure hiding, not this case. Author-side hash-file generation only; not in shipped artifacts.
3. WI 4.8 case 6c needed pre-commit/uncommitted-in-worktree pass branch (hash file is untracked at verification time). Implementer added; check still runs after the file commits.

### Notes

- Phase 4 is the largest single-phase scope (678 plan-lines). Implementable in one agent run.
- Step D.5's migration logic uses pure bash + git hash-object (no jq, no eval, no `$(())` over user input).
- Per-file `.zskills/tier1-migration-deferred` marker design (D24) lets users decline migration with a single flag without re-prompting on subsequent runs.

---

## Phase — 3b Cross-skill caller sweep + port.sh fix [UNFINALIZED]

**Plan:** plans/SCRIPTS_INTO_SKILLS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-scripts-into-skills-plan (will be removed after combined 3a+3b PR squash)
**Branch:** feat/scripts-into-skills-plan
**Commits:** 64dc37d (Phase 3b impl + orchestrator fixups), 4925f8b (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 3b.1 | Cross-skill caller sweep across 13 skills (do, run-plan, fix-issues, quickfix, research-and-go, research-and-plan, create-worktree, commit, briefing, manual-testing, fix-report, verify-changes, update-zskills) | Done | 64dc37d |
| 3b.2 / 3b.2.a | CLAUDE.md + README.md updates; helper-scripts list rewritten with script-ownership.md pointer | Done | 64dc37d |
| 3b.3-3b.6b | sanitize-pipeline-id, create-worktree, land-phase, write-landed, clear-tracking, port.sh callers converted | Done | 64dc37d |
| 3b.7 | Hook help-text in template + .claude mirror updated (lines 89, 91, 103, 114, 194, 208) | Done | 64dc37d |
| 3b.8 | 13 skill mirrors regenerated via mirror-skill.sh; all `diff -r` clean | Done | 64dc37d |
| 3b.9 | 6 test files updated with new script paths (test-canary-failures, test-create-worktree, test-hooks, test-port, test-quickfix, test-skill-conformance) | Done | 64dc37d |
| 3b.10 | `bash tests/run-all.sh` exits 0 (931/931) | Done | 64dc37d |
| (extra) | port.sh PROJECT_ROOT bug fix (3a verifier-flagged): derive from `git rev-parse --show-toplevel`, not `$SCRIPT_DIR/..` | Done | 64dc37d |
| (orch) | /quickfix `$CLAUDE_PROJECT_DIR` → `$MAIN_ROOT` (set -u safety) + test-quickfix fixture target update | Done | 64dc37d |

### Verification

- Test suite: PASSED (931/931, +37 from Phase 3a's 894 baseline)
- All 37 cross-skill caller failures resolved
- port.sh from main repo path returns `8080` (default_port from config) — bug fixed
- Mirror parity holds for all 13 swept skills
- /quickfix runs cleanly under `set -u` (no unset CLAUDE_PROJECT_DIR trip)

### PLAN-TEXT-DRIFT findings

3 minor AC-text drift tokens (non-blocking):
1. WI 3b.6b.x AC contradicts WI text (says SKIP `:326` PORT_SCRIPT row but AC says zero `scripts/port.sh` matches in the file).
2. WI 3b.7 AC's wording about `grep -c 'scripts/clear-tracking'` is incorrect (substring match overcounts new-form paths).
3. WI 3b.6b line numbers stale (off-by-one: `:326` → `327`, `:414` → `415`, `:704` → `705`).

All 3 are AC formulation drift that the verifier flagged for refine; none block correctness.

### Combined 3a+3b landing

Phase 3a was a midpoint with 37 intentionally red tests (per plan's allowlist contract). Phase 3b's commit lands ON TOP of Phase 3a's commits in the same feature branch. Phase 3b's PR (opened in this phase's Phase 6) presents the COMBINED 3a+3b work — green CI, clean squash to main.

The orchestrator's 2 fixups were folded into Phase 3b's `64dc37d` commit by the verifier:
- /quickfix's `$CLAUDE_PROJECT_DIR` → `$MAIN_ROOT` (avoids `set -u` unbound-var trip in fixture sub-shells)
- test-quickfix fixture target moved to `.claude/skills/create-worktree/scripts/` (matches SKILL's new path)

### Notes

- This is the largest phase by file count (52 modified files spanning skill text, hooks, tests, docs).
- Phase 4 onwards (`/update-zskills` install flow rewrite, tests sweep, docs close-out) follow the now-clean baseline.

---

## Phase — 3a Move shared Tier-1 scripts + default_port reconcile [UNFINALIZED]

**Plan:** plans/SCRIPTS_INTO_SKILLS_PLAN.md
**Status:** Completed (verified) — landing deferred to Phase 3b
**Worktree:** /tmp/zskills-pr-scripts-into-skills-plan (persisting across phases)
**Branch:** feat/scripts-into-skills-plan
**Commits:** 596a498 (impl: 7 git mv + schema + config + template), 61f41a2 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 3a.1 | create-worktree.sh + worktree-add-safe.sh moved to skills/create-worktree/scripts/ | Done | 596a498 |
| 3a.2 | install-integrity gate updated to use $SCRIPT_DIR/sanitize-pipeline-id.sh | Done | 596a498 |
| 3a.3 | sanitize-pipeline-id.sh moved to skills/create-worktree/scripts/ | Done | 596a498 |
| 3a.4 | land-phase.sh + write-landed.sh moved to skills/commit/scripts/ | Done | 596a498 |
| 3a.4b | clear-tracking.sh moved to skills/update-zskills/scripts/ | Done | 596a498 |
| 3a.4c | port.sh moved + config-driven default_port (BASH_REMATCH) + schema field added | Done | 596a498 |
| 3a.4c.i | Greenfield template gained `"default_port": 8080,` | Done | 596a498 |
| 3a.5 | Mirrors regenerated for create-worktree, commit, update-zskills | Done | 596a498 |
| 3a.6 | Positive-pass invocation: bash skills/create-worktree/scripts/create-worktree.sh --help | Done | exit 0 with usage |

### Verification

- 7 scripts moved with rename detection (history preserved via `git log --follow`)
- All ACs pass (structural + positive-pass invocation + scoped test allowlist intent)
- Mirror parity holds for all 3 skills
- create-worktree.sh peer invocations now use `$SCRIPT_DIR/...` (no `$MAIN_ROOT/scripts/...` references)
- port.sh reads `dev_server.default_port` from config via BASH_REMATCH; schema + this-repo config + greenfield template all updated

### Test results: 894/931 (37 fails — all Phase 3b scope)

Per the plan's "tests intentionally red allowlist" contract (DA-4 fix), Phase 3a is a midpoint:
- **Allowlisted failures** (24 fails): test-canary-failures (20), test-quickfix (4) — both reference cross-skill paths to land-phase.sh, write-landed.sh, sanitize-pipeline-id.sh in `tests/` files. Phase 3b's WI 3b.9 sweeps these.
- **Allowlist drift** (13 fails): test-hooks (10) + test-port (3) — fail for the SAME root cause as the allowlisted suites (cross-skill `tests/` references to moved scripts) but were not enumerated in the plan's allowlist. Independently verified by both implementer and verifier; uniform `bash: scripts/<x>.sh: No such file` failure mode.

Verifier confirmed 100% of failures are Phase-3b-scope (cross-skill `tests/` paths to moved scripts). Zero failures expose a Phase 3a regression.

### PLAN-TEXT-DRIFT findings

1. **Allowlist mis-enumeration**: plan's allowlist names 5 suites, reality is 4 fail-suites with 2 not on allowlist. Phase 3b's verifier should re-state the allowlist from observed failures rather than blindly checking the plan's 5-suite list.
2. **port.sh PROJECT_ROOT bug**: `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"` at line 12 of moved port.sh resolves to `<repo>/skills/update-zskills` instead of repo root. Main-repo invocations now return hash-derived port instead of `default_port`. The `_ZSK_REPO_ROOT` `git rev-parse --show-toplevel` recovery rescues config reading, but the main-repo equality check `[[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]` will never fire. Spec WI 3a.4c didn't direct this fix, so out-of-scope per implementer; Phase 3b should patch it via deriving PROJECT_ROOT from `git rev-parse --show-toplevel` at invocation time, not from `$SCRIPT_DIR/..`.

### Landing strategy

Per plan ("Phase 3a is intentionally a mid-state ... do NOT block the PR"), Phase 3a does NOT open a PR or trigger CI gating on its own. Commits are pushed to the feature branch; Phase 3b adds its commits to the same branch and Phase 3b's Phase 6 opens the PR + polls CI (now green) + auto-merges the combined squash.

The PR-mode `.landed` marker is NOT written for Phase 3a (worktree must persist for Phase 3b's resume via `--allow-resume`).

---

## Phase — 2 Move single-owner Tier-1 scripts to owning skills [UNFINALIZED]

**Plan:** plans/SCRIPTS_INTO_SKILLS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-scripts-into-skills-plan
**Branch:** feat/scripts-into-skills-plan
**Commits:** e401209 (impl: 7 git mv + 22 file mods), 3716452 (tracker mark in-progress)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 2.1 | apply-preset.sh moved to skills/update-zskills/scripts/ | Done | e401209 |
| 2.2 | compute-cron-fire.sh moved to skills/run-plan/scripts/ + 4 callsites | Done | e401209 |
| 2.2b | plan-drift-correct.sh moved to skills/run-plan/scripts/ + 8 callsites + test path + TRACKING_NAMING.md | Done | e401209 |
| 2.3 | post-run-invariants.sh moved + 3 callsites | Done | e401209 |
| 2.4 | briefing.cjs + briefing.py moved + 11 callsites + language-appropriate self-doc idioms | Done | e401209 |
| 2.5 | update-zskills dependency check retains both halves (artifact + interpreter) | Done | e401209 |
| 2.6 | tests/test-briefing-parity.sh updated | Done | e401209 |
| 2.7 | tests/test-apply-preset.sh updated | Done | e401209 |
| 2.7b | statusline.sh moved + Step C.5 fixed + +x bit set | Done | e401209 |
| 2.8 | Mirrors regenerated for 3 skills via mirror-skill.sh | Done | e401209 |
| 2.8b | scripts/__pycache__/ verified absent | Done | e401209 |
| 2.9 | bash tests/run-all.sh passes | Done | 931/931 |

### Verification

- Test suite: PASSED (931/931, no delta from baseline)
- All scripts moved with `git mv`-equivalent rename detection (history preserved via `git log --follow`)
- All 7 scripts have correct +x bits (statusline.sh required `git update-index --chmod=+x`)
- No old `scripts/<name>` references in skills/ or .claude/skills/ (disambiguated grep returns 0)
- Mirror parity: `diff -r skills/<name> .claude/skills/<name>` empty for update-zskills, run-plan, briefing
- Briefing dependency check retains the artifact half (skills/briefing/scripts/briefing.* still listed)
- Self-doc idioms language-appropriate: path.basename(__filename) in .cjs, os.path.basename(sys.argv[0]) in .py, no $(basename "$0") leak

### PLAN-TEXT-DRIFT findings

5 tokens flagged by implementer + verifier (independent re-detection confirmed all 5):
- 2 are AC grep-overmatch issues (literal `grep 'scripts/X'` matches new-form `.claude/skills/<owner>/scripts/X` because new path is suffix-equal). Disambiguated form `(^|[^./])scripts/X` returns 0 outside intentional STALE_LIST. AC intent satisfied.
- 3 are line-number staleness in plan WI prose (work was done via grep, not line numbers).

None blocked correctness. Phase 3.5 didn't auto-correct because the drift category here is "AC formulation pattern" not "numeric value off by N%" — the disambiguated greps are already in the plan as fallback.

### Notes

- Cross-skill callers (other skills that call these moved scripts) are Phase 3b's scope and remain untouched.
- HANDOFF_CANARY_FAILURE_INJECTION.md:223 references `scripts/post-run-invariants.sh` — outside skills/.claude/skills scope; will be swept in Phase 3b or Phase 6 docs sweep.
- STALE_LIST in script-ownership.md intentionally retains old `scripts/<name>` paths (Phase 4 deletion list); not in scope to change.

---

## Phase — 1 Inventory cleanup: fix dead refs, write ownership registry [UNFINALIZED]

**Plan:** plans/SCRIPTS_INTO_SKILLS_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-scripts-into-skills-plan
**Branch:** feat/scripts-into-skills-plan
**Commits:** 7fc20c4 (orchestrator H4→H3 heading fix), 49c666b (impl + ownership registry), bb4d661 (tracker + prose drift fix)

### Work Items

| # | Item | Status | Source |
|---|------|--------|--------|
| 1.2 | 3 dead script refs in skills/fix-issues/SKILL.md replaced with manual gh recipes (skipped-issues.cjs, sync-issues.js, issue-stats.js) | Done | 49c666b |
| 1.3 | review-feedback.js ref stripped from skills/review-feedback/SKILL.md | Done | 49c666b |
| 1.4 | skills/update-zskills/references/script-ownership.md written (18 rows: 14 Tier-1 + 4 Tier-2). Plan Overview table synchronized | Done | 49c666b |
| 1.5 | Mirror parity for fix-issues, review-feedback, update-zskills | Done | 49c666b |
| 1.6 | rel-root-cw-cw-smoke-43859 verified absent; __pycache__ deferred to Phase 2 WI 2.8b per plan | Done | 49c666b |
| (orchestrator) | H4 → H3 phase sub-heading restoration (refine-plan output had wrong levels) | Done | 7fc20c4 |
| (orchestrator) | Phase 4 tracker mark-in-progress + 3 prose drift fixes (verifier-flagged "13 moves" → "14"; Tier-2 list updated) | Done | bb4d661 |

### Verification

- Test suite: PASSED (931/931, no delta from baseline — docs-only phase)
- All 9 acceptance criteria verified by independent verification agent
- Mirror parity holds for all 3 skills (`diff -r` clean)
- Verifier independently re-detected 3 PLAN-TEXT-DRIFT prose drifts (13→14 / Tier-2 omitted mirror-skill.sh) — fixed inline in commit `bb4d661`
- `script-ownership.md` registry contract: 14 Tier-1 + 4 Tier-2 rows; canonical Tier-1 parser; STALE_LIST documented

### Notes

- Phase 1 is foundational/registry only — no script moves yet.
- Phase 2 will move single-owner Tier-1 scripts (apply-preset, compute-cron-fire, post-run-invariants, briefing.*, statusline) into their owning skills' `scripts/` subdirs.
- Phase 3a/3b will move shared Tier-1 scripts (create-worktree, worktree-add-safe, land-phase, etc.) and sweep cross-skill callers.
- Phase 4 will rewrite `/update-zskills` install flow.
- Phase 5 will sweep tests + README/CLAUDE.md/CLAUDE_TEMPLATE.
- Phase 6: docs and close-out.

### PLAN-TEXT-DRIFT findings

3 prose drifts caught by the verifier (binding ACs all passed):
- Line 84 ("13 moves" → 14): fixed inline in bb4d661
- Line 86 (Tier-2 list omitted mirror-skill.sh): fixed inline
- Line 2414 ("13 scripts moved" → 14): fixed inline

These were stragglers from the refine-plan output where per-table counts synced but free-form prose did not. All 3 corrected on the feature branch.
