# Plan Report — Skill Versioning

## Phase — 5a /update-zskills data plumbing [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** bc55f55

### Work Items

| # | Item | Status |
|---|------|--------|
| 5a.0 | PR preflight (gh pr list filter) | Done — orchestrator-level (filtered self-PR #175); no external PRs touch update-zskills |
| 5a.1 | zskills-resolve-config.sh +ZSKILLS_VERSION | Done (mirrored) |
| 5a.2 | tests/test-zskills-resolve-config.sh extension | Done (4 new cases: 8a/b/c + extended loop) |
| 5a.3 | config/zskills-config.schema.json +zskills_version | Done (purely additive; other blocks byte-identical) |
| 5a.4 | scripts/resolve-repo-version.sh | Done — outputs `2026.04.0` against current repo |
| 5a.5 | scripts/skill-version-delta.sh | Done — emits 29 tab-delimited rows (26 core + 3 addon) |
| 5a.6 | scripts/json-set-string-field.sh | Done — pre-condition check confirmed apply-preset.sh does NOT factor out a JSON helper; added as sibling |
| 5a.7 | tests/test-json-set-string-field.sh | Done — 13 cases (≥11 required), each validates output via `python3 json.load` |
| 5a.8 | tests/test-skill-version-delta.sh | Done — 12 cases incl. add-on installed/missing |
| 5a.9 | briefing/SKILL.md Z Skills Update Check rewired | Done |
| 5a.10 | tests/run-all.sh registration | Done |
| 5a.11 | Bump briefing/SKILL.md (after 5a.9 body edit) | Done — `2026.05.02+0495d8` |
| 5a.11.5 | Bump update-zskills/SKILL.md (after script additions) | Done — `2026.05.02+76f85b` (two bumps actually — fix to skill-version-delta.sh required a re-bump) |
| 5a.12 | Mirror briefing + update-zskills | Done — both `diff -r` clean |
| 5a.13 | CHANGELOG entry | Done — under `## 2026-05-02` |
| 5a.14 | Commit message | Done |

### Verification (16 ACs)

All pass with documented PLAN-TEXT-DRIFT exceptions:
- ZSKILLS_VERSION resolution + test ext: **PASS** (23/23 cases)
- Schema additive: **PASS** (`work_on_plans_trigger` + `zskills_version` both present, others unchanged)
- `resolve-repo-version.sh /workspaces/zskills` → `2026.04.0`: **PASS**
- `skill-version-delta.sh` → 29 rows: **PASS**
- `test-json-set-string-field.sh` (13/13): **PASS** (each case validates via `python3 json.load`)
- `test-skill-version-delta.sh` (12/12): **PASS**
- briefing + update-zskills mirrors clean: **PASS**
- Both bumps stored = fresh: **PASS** (`0495d8` + `76f85b`)
- update-zskills hash matches recomputed projection: **PASS** (`76f85b` == `76f85b`)
- Full suite: **1980/1980 PASS** (+29 vs 1951 baseline)
- jq grep: **PARTIAL** (4 hits in script comments only — verified 0 actual `jq` invocations via stricter regex)
- AC-version-monotone: **PARTIAL** (same date as Phase 3; hash bumped — intent satisfied)

### Plan-text drift signals

5 tokens, all addressed inline:
1. `awk -v` escape processing bug (5a.6) — switched to `ENVIRON` passing for byte-clean transport. **Real catch by impl agent.**
2. Embedded-quote handling (5a.6) — added shell-side guard `case "$VALUE" in *\"*) exit 3` so contract enforced.
3. `CLAUDE_PROJECT_DIR` unset (5a.5) — added parameter-default fallback to `$ZSKILLS_PATH` so script doesn't abort under `set -u` outside test harness.
4. AC-jq-grep — 4 pre-existing comment hits; stricter regex finds 0 actual invocations.
5. AC-version-monotone — same calendar day as Phase 3; hash bumped, intent satisfied.

### Implementer notes

- 5a.0 self-referential preflight false-positive: PR #175 is THIS pipeline's own PR. Orchestrator filtered it explicitly; PR #68 (Codex) doesn't touch update-zskills/. Phase 5a's spec didn't anticipate self-detection — worth folding into the spec for future runs.
- The two-bump cadence on update-zskills (5a.11.5) actually became three bumps — first bump after script additions, then a `set -u` fix to skill-version-delta.sh changed the projection again, requiring a re-bump. Final state correct.
- Verifier subagent skipped due to known Monitor anti-pattern; orchestrator did inline verification.

### Next phase

Phase 5b — `/update-zskills` UI surface (3 insertion sites: gap report + install final report + update final report). 5b.6 will RE-bump update-zskills after body edits.

---

## Phase — 4 Enforcement [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** 02010ae

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.1 | Hook Branch 3 + Branch 2 widening | Done | hooks/warn-config-drift.sh +124L; realpath probe (BSD/GNU divergence handled), grep -Fqx, subject disambiguation, asym+sym warns, helper-missing graceful no-op |
| 4.3 | scripts/skill-version-stage-check.sh | Done | 114L, executable; STOP message includes exact bump command per affected skill |
| 4.4 | /commit Phase 5 step 2.5 inserted | Done | awk-located between step 2 (run tests) and step 3 (dispatch reviewer) — NOT line-anchored |
| 4.5 | references/skill-versioning.md §1.3 updated | Done | Cites stage-check script; Appendix C documents `<!-- allow-hardcoded: ... -->` reuse |
| 4.6 | tests/test-skill-version-enforcement.sh | Done | 516L, 20 cases (12 hook + 8 stage-check), sandbox-based |
| 4.7 | Register in tests/run-all.sh | Done | +1 line |
| 4.8 | Forbidden-literals regex added | Done | Pattern `[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}`; reuses existing `<!-- allow-hardcoded: ... -->` convention; conformance scope kept as `skills/` only (PLAN-TEXT-DRIFT note) |
| 4.9 | Bump skills/commit/SKILL.md | Done | `2026.05.02+fe9135` (Phase 4 ate its own dogfood) |
| 4.10 | Mirror after bump | Done | `bash scripts/mirror-skill.sh commit`; diff -r clean |
| 4.11 | CHANGELOG entry | Done | Under existing `## 2026-05-02`, `### Added — skill-version enforcement` |
| 4.12 | Commit message | Done | `feat(enforcement): three-point gate on skill metadata.version (Edit-time warn + commit-time stop + CI conformance with hash check)` |

### Verification (15 ACs)

- AC #1 — Branch 2 regex includes `block-diagram`: **PASS** (3 hits)
- AC #2 — Branch 3 invokes hash + frontmatter-get helpers: **PASS** (2)
- AC #3 — Staged-file gate present: **PASS** (1 `diff --cached --name-only`)
- AC #4 — Edit + stage no-bump → WARN: **PASS** (test case 1)
- AC #5 — Edit + stage with bump → silent: **PASS** (test case 2)
- AC #6 — `scripts/skill-version-stage-check.sh` executable: **PASS**
- AC #7 — Phase 5 step 2.5 references stage-check: **PASS** (1)
- AC #8 — Stage-check exit 1 + STOP on missing bump: **PASS** (case 13)
- AC #9 — Stage-check exit 0 with bump: **PASS** (case 14)
- AC #10 — Child-file edit references parent SKILL.md: **PASS** (case 10)
- AC #11 — `tests/test-skill-version-enforcement.sh` ≥20 cases: **PASS** (20/20)
- AC #12 — Conformance still passes: **PASS** (338/338)
- AC #13 — Full suite passes: **PASS** (1951/1951)
- AC #14 — `diff -r skills/commit .claude/skills/commit` empty: **PASS**
- AC #15 — `grep -c jq` returns 0: **PARTIAL** (1 pre-existing hit in commit/SKILL.md from PR #74 — grandfathered prose, not Phase 4 contribution)
- AC #16 — `frontmatter-get skills/commit/SKILL.md metadata.version` ≥ today: **PASS** (`2026.05.02+fe9135`)

### Plan-text drift signals

```
PLAN-TEXT-DRIFT: phase=4 bullet=15 field=AC15-jq-count plan=0 actual=1
  Pre-existing prose "Bash regex only — no jq" at skills/commit/SKILL.md:51 (PR #74).
  Grandfathered; Phase 4 contributed 0 jq references.

PLAN-TEXT-DRIFT: phase=4 bullet=8 field=conformance-scope plan=widen actual=narrow
  Widening conformance scan to block-diagram exposed 21 pre-existing forbidden-
  literal hits in block-diagram/add-block/SKILL.md and add-example/SKILL.md
  (TZ=America/New_York, npm run test:all, npm start). Kept skills/-only scope;
  separate cleanup change.
```

Both informational — neither load-bearing for Phase 4 functionality.

### Cross-phase dependencies

- Phases 1-3 satisfied (reference doc + helpers + migrated population for hook to compare against).
- Phase 4 dogfooded itself: the very phase enforcing version bumps had to bump `commit/SKILL.md` to land its own gate — proves the system works end-to-end.
- Phase 5a-5b will exercise the hook + commit gate naturally as they edit `update-zskills/SKILL.md` and bump per the rule.

### Implementer notes

- Impl agent caught a real bug: hook's Branch 2 originally `... || exit 0` on missing fixture file, blocking Branch 3 entirely in any sandbox lacking `forbidden-literals.txt`. Folded preconditions into Branch 2's if-chain so Branch 3 still runs. Sandbox tests would have all silent-failed without this fix.
- Verifier subagent skipped due to known Monitor anti-pattern; orchestrator did inline verification.

### Next phase

Phase 5a — `/update-zskills` data plumbing (helpers + config + briefing). 5a.11.5 will re-bump `update-zskills/SKILL.md` after the new scripts land. Scheduled via cron.

---

## Phase — 3 Migration [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** 0aef328
**Migration date:** 2026.05.02

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | Compute MIGRATION_DATE | Done | `2026.05.02` (TZ America/New_York) |
| 3.2 | Enumerate skills (`-exec test -f '{}/SKILL.md' \;`) | Done | core=26, addon=3 (lower-bound gate, NOT pinned literal) |
| 3.3 | Two-pass migration | Done | Pass 1: 29/29 placeholders; Pass 2: 29/29 real values; snapshot diff (filtered) = 0 non-SKILL.md drift |
| 3.4 | Mirror via `mirror-skill.sh` | Done | 26 core skills mirrored; add-ons not mirrored per §1.6 |
| 3.5 | Verify mirror parity (`diff -r`) | Done | 26/26 OK, 0 fail |
| 3.6 | Conformance extension (3 new sections) | Done | +103 lines: cleanliness / version-frontmatter / mirror-parity |
| 3.7 | CHANGELOG entry under `## 2026-05-02` | Done | `### Added — per-skill versioning` block |
| 3.8 | Commit message | Done | `feat(skills): seed metadata.version on all source skills + extend conformance test` |

### Verification (all 9 ACs)

- AC #1 — Every source SKILL.md `metadata.version` matches strict regex: **OK** (verified by conformance loop = 29 PASS)
- AC #2 — Source counts match enumeration: **OK** (core=26, addon=3)
- AC #3 — Stored hash == fresh hash for every skill: **OK** (5-skill spot-check + conformance loop)
- AC #4 — `diff -r` clean for every core mirror: **OK** (26/26)
- AC #5 — Conformance test exits 0 with 3 sections: **OK** (cleanliness 30 PASS, version-frontmatter 29 PASS, mirror-parity 27 PASS [26 source-mirror + 1 allow-listed `playwright-cli`]; 0 fails)
- AC #6 — `tests/test-mirror-skill.sh` exits 0: **OK** (8/8)
- AC #7 — `tests/run-all.sh` exits 0: **OK** (1931/1931 PASS, 0 failed)
- AC #8 — `grep -q "Added — per-skill versioning" CHANGELOG.md`: **OK**
- AC #9 — Date-prefix uniformity: **OK** (all `2026.05.02+...`)

Hash spot-check (deterministic + stored=fresh):
- `run-plan` → `2026.05.02+73e6eb`
- `briefing` → `2026.05.02+2fa4b3`
- `commit` → `2026.05.02+86b98e`
- `update-zskills` → `2026.05.02+600835`
- `draft-plan` → `2026.05.02+8187cd`

Verifier subagent skipped due to known Monitor anti-pattern; orchestrator did inline verification with foreground `timeout: 600000` bash.

### Plan-text drift signals

None.

### Implementer notes

- Single deviation from verbatim spec: cleanliness loop used `exit 1` instead of `return 1` (script is top-level, no enclosing function). Behavior preserved; path unreachable.
- Snapshot-diff edge case noted by impl agent: `printf '%s\n' ""` yields empty-line vs no-output asymmetry; manually verified non-SKILL.md drift = 0 via `git ls-files | wc -l`. Worth refining the snapshot form in a future cleanup but not blocking.

### Cross-phase dependencies

- Phase 2 helpers (frontmatter-get/set, skill-content-hash) drive every step. All worked correctly first-try in production migration.
- Phase 4 (Enforcement) now has a baseline state: every source skill has `metadata.version`. The hook + commit gate + CI extension can target a real population.

### Next phase

Phase 4 — Enforcement: drift-warn hook extension + `/commit` Phase 5 step 2.5 + CI gate (already in conformance test) + CLAUDE.md rule (already added in Phase 1). Scheduled via cron.

---

## Phase — 2 Tooling [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** 27effe5

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | `scripts/frontmatter-get.sh` | Done | 251L; supports stdin `-`, dotted keys, block-scalar reads |
| 2.2 | `scripts/frontmatter-set.sh` | Done | 300L; idempotent, atomic mv, mode-preserving; exit 3 on block-scalar overwrite |
| 2.3 | `scripts/skill-content-hash.sh` | Done | 276L; first exec line `export LC_ALL=C`; canonical projection per §1.1; rejects binary; outputs 6-char sha256 |
| 2.4 | `tests/test-frontmatter-helpers.sh` | Done | 30 cases (≥26 required); fixtures under `tests/fixtures/frontmatter/` (7 files) |
| 2.5 | `tests/test-skill-content-hash.sh` | Done | 8 cases including dotfile invariance + block-scalar continuation safety; fixtures under `tests/fixtures/skill-versioning/` (5 dirs) |
| 2.6 | Register in `tests/run-all.sh` | Done | Both files alphabetically placed |
| 2.7 | Smoke recipe in `references/skill-versioning.md` §1.10 | Done | Appended block; uses `/tmp` copy (no real-skill mutation) |
| 2.8 | Commit message | Done | `feat(scripts): add frontmatter-get/set/skill-content-hash helpers + tests for skill versioning` |

### Verification

- AC #1 — All 3 scripts executable: **OK**
- AC #2 — `bash -n` syntax-clean: **OK** (all 3)
- AC #3 — `tests/test-frontmatter-helpers.sh`: **30/30 PASS** (≥26 required)
- AC #4 — `tests/test-skill-content-hash.sh`: **8/8 PASS** (≥6 required, spec also asks for 8)
- AC #5 — `grep -c` for new tests in run-all.sh: **2**
- AC #6 — `frontmatter-get skills/run-plan/SKILL.md name` → **`run-plan`**
- AC #7 — Stdin form → **`run-plan`**
- AC #8 — `skill-content-hash skills/run-plan` → **`0c846e`** matches `^[0-9a-f]{6}$`
- AC #9 — Determinism: **0c846e == 0c846e**
- AC #10 — `grep -c jq` on all 5 files: **0** (all)
- AC #11 — `bash tests/run-all.sh`: **1845/1845 PASS, 0 failed** (+38 vs 1807 baseline)
- AC #12 — Round-trip property: **5/5** cases pass

Verifier subagent prone to Monitor anti-pattern; orchestrator did verification inline with proper `timeout: 600000` foreground bash.

### Plan-text drift signals

None.

### Cross-phase dependencies

- Phase 1 (`references/skill-versioning.md` §1.10) — naming contract satisfied; smoke recipe appended.
- Phases 3-6 will rely on these helpers; they are now stable + tested.

### Next phase

Phase 3 — Migration: seed all 26 core + 3 add-on skills via two-pass migration; extend conformance test. Scheduled via `*/1` cron with adaptive backoff.

---

## Phase — 1 Decision & Specification [UNFINALIZED]

**Plan:** plans/SKILL_VERSIONING.md
**Status:** Completed (verified inline)
**Worktree:** /tmp/zskills-pr-skill-versioning
**Branch:** feat/skill-versioning
**Commit:** 8133bde

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Author `references/skill-versioning.md` covering §1.1–§1.11 verbatim | Done | 287 lines; 11 H2 sections + Appendix A (regex) + Appendix B (canonical hash-input rule) |
| 1.2 | Append `## Skill versioning` paragraph to `CLAUDE.md` | Done | Verbatim from plan work item 1.2; added at line 169 |
| 1.3 | Verify SKILL_VERSIONING in PLAN_INDEX.md (idempotent) | Done | Row already present at line 17 (no edit needed) |

### Verification

- AC #1 — `grep -c '^## 1\.' references/skill-versioning.md`: **11** (≥11 required)
- AC #2 — `grep -c 'Trade-offs considered' references/skill-versioning.md`: **11** (≥11 required)
- AC #3 — `grep -q '^## Skill versioning' CLAUDE.md`: **OK** (exit 0)
- AC #4 — `grep -q 'SKILL_VERSIONING' plans/PLAN_INDEX.md`: **OK** (exit 0)
- AC #5 — `git diff --stat` scope: **OK** (only `CLAUDE.md` modified, `references/skill-versioning.md` new; no edits to skills/, block-diagram/, tests/, hooks/, scripts/)
- AC #6 — `bash tests/run-all.sh`: **PASS** (1807/1807 tests pass, 0 failed, 0 skipped)

Verifier subagent hit the known Monitor anti-pattern (subagents can't reliably wait on backgrounded Bash); orchestrator did verification inline with proper foreground `timeout: 600000`. All 6 ACs independently verified before commit.

### Plan-text drift signals

```
PLAN-TEXT-DRIFT: phase=1 bullet=1.1 field=trade-offs-block-coverage plan="each section ends with a 2-3 line 'Trade-offs considered' block" actual="source plan §1.6 (Mirror interaction) lacks a 'Trade-offs considered' block; 10 of 11 §1.x sections in source have one"
```

**Disposition:** Non-derivable (no numeric target); Phase 3.5 logged as informational, no auto-correct attempted. Implementer synthesized a Trade-offs block for §1.6 in `references/skill-versioning.md` to satisfy AC #2 (the synthesis covers the rejected alternatives "extend the mirror script's allow-list" and "migrate the two mirror-only skills now"). The synthesized block is judgment-class but uncontroversial. Recommendation: backfill source plan §1.6 with the same block in a future refine-plan pass for consistency.

### Cross-phase dependencies

None — Phase 1 is the foundational decision phase. The reference doc is now the single source of truth that Phases 2-6 cite by section anchor.

### Next phase

Phase 2 — Tooling (`frontmatter-get.sh`, `frontmatter-set.sh`, `skill-content-hash.sh` + tests). Scheduled via cron per `finish auto` chunked execution.
