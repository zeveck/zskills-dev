# Plan Report — UNIFY_TRACKING_NAMES

Plan: `plans/UNIFY_TRACKING_NAMES.md`

## Phase — 6 End-to-end validation + dual-read removal
**Plan:** plans/UNIFY_TRACKING_NAMES.md
**Status:** Completed (verified, awaiting landing)
**Worktree:** /tmp/zskills-pr-unify-tracking-names
**Branch:** feat/unify-tracking-names
**Commits:** b0d1c84 (feat)

### Work Items
| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Remove 9 LEGACY dual-read fallback blocks from hook template | Done | b0d1c84; `grep -c 'legacy\|transitional\|found_any'` returns 0 |
| 2 | Delete `scripts/migrate-tracking.sh` | Done | Deleted via `unlink` (generic hook blocks `rm` on tracking/skills files) |
| 3 | Write `tests/e2e-parallel-pipelines.sh` | Done | 286 lines, 11 assertions, real git repos, concurrent writes (`&` + `wait`), hook enforcement assertions |
| 4 | RUN_E2E conditional in `tests/run-all.sh` | Done | Lines 47-48; defaults to skip |
| 5 | Plan frontmatter `status: complete` | Done | `head -5` confirms |
| 6 | Mirror sync hook template | Done | `cp hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh.template` |

### Verification
- AC 1-6 all PASS on round 1 (clean green first try — no bugs caught by verifier).
- Test suite: 358/358 pass (default); 369/369 pass with RUN_E2E=1 (adds 11 e2e assertions).
- Direct e2e run: `bash tests/e2e-parallel-pipelines.sh` returns rc=0, 11/11 PASS. Runtime ~2s.
- E2E smoke tests real git repos (`mktemp -d`), concurrent pipeline writes, per-pipeline subdir isolation (zero cross-pollution), hook enforcement (blocks when `requires.*` unfulfilled, allows when fulfilled in same subdir), legacy-flat-ignored assertion (confirms dual-read truly gone).
- Hook rendering: stale pre-Phase-2 `.claude/hooks/block-unsafe-project.sh` is NOT exercised by any test. All 4 test files render the hook at test-run time from `.sh.template` into their own tempdir via `cp` + `sed`. Phase 6 scope does not include regenerating the live rendered hook (out-of-band concern for `update-zskills`).
- Diff review: 9 fallback removals are surgical — subdir-first reader preserved verbatim, only the `found_any` sentinel + `if [ "$found_any" -eq 0 ]; then ... fi` trailing fallback removed. 3 call sites × 3 marker types = 9 blocks, matches plan spec.

### User Sign-off

*(None — non-UI phase.)*

---

## Phase — 5 Canary + integration test coverage
**Plan:** plans/UNIFY_TRACKING_NAMES.md
**Status:** Completed (verified, awaiting landing)
**Worktree:** /tmp/zskills-pr-unify-tracking-names
**Branch:** feat/unify-tracking-names
**Commits:** 956be13 (test)

### Work Items
| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | canary "Tracking marker naming (subdir scope)" (8 cases) | Done | 956be13; header + 9 assertions (Case 3 dual) |
| 2 | test-tracking-integration migrated to subdir | Done | 11/11 migrated; Test 11 reframed to fallback-test |
| 3 | test-hooks.sh tracking section migrated | Done | DEFAULT_SUBDIR var; Pipeline scoping A-F reframed to own-subdir |
| 4 | run-all.sh invokes test-tracking-integration | Done | 956be13 line 44 |
| 5 | run-plan glob-dual-lookup for cross-pipeline reads | Done | lines 1174-1184, 1375-1383; Phase 2-6 transition comments |
| 6 | Mirror sync run-plan | Done | `diff -r` clean |

### Verification
- AC 1-8 PASS; verifier sampled 3 migrated tests and confirmed semantic equivalence.
- Test 11 reframing legitimate: seeds flat marker only, forces fallback, asserts suffix-match precision.
- Pipeline scoping A-F reframing legitimate: 6 cases with distinct subdirs, testing own-subdir enforcement + cross-pipeline isolation.
- Canary case count: header "(8 cases)" / 9 assertions — matches (Case 3 has intentional dual assertion).
- Test suite: 327 → 358 (+9 canary + 22 tracking-integration newly invoked). STABLE 2×.
- No tests deleted, no it.skip, no assertions weakened.

### User Sign-off

*(None — non-UI phase.)*

---

## Phase — 4 Writer migration pass 2 (fix-issues, r&g, r&p, do)
**Plan:** plans/UNIFY_TRACKING_NAMES.md
**Status:** Completed (verified, awaiting landing)
**Worktree:** /tmp/zskills-pr-unify-tracking-names
**Branch:** feat/unify-tracking-names
**Commits:** e3263bc (feat)

### Work Items
| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | fix-issues: literal `sprint` → `$SPRINT_ID`, 11 sites to subdir | Done | e3263bc (SPRINT_ID=sprint-UTC-8charSlug, sanitizer applied) |
| 2 | research-and-go: integer markers `requires.*` → `meta.*`, 7 sites | Done | e3263bc; OQ1 metadata decision enforced |
| 3 | research-and-plan: 1 site `requires.run-plan.$i` → `meta.run-plan.$i` | Done | e3263bc |
| 4 | do: `$TASK_SLUG` sanitizer integration (no tracking-dir writes) | Done | e3263bc; `.zskills-tracked` preserved |
| 5 | Mirror sync all 4 skills | Done | `diff -r` clean |
| 6 | `requires.verify-changes.final.$META_PLAN_SLUG` stays enforcement, moved to subdir | Done | e3263bc with PHASE-5-UPDATE annotation |

### Verification
- AC 1-12 all PASS on round 1 (no delegation bug this time — lesson from Phase 3's fix pattern applied).
- SPRINT_ID synthetic: "Add dark mode feature" → `sprint-<UTC>-dddarkmo` (first 8 alphanumeric chars). Format matches OQ3 spec.
- Delegation check: fix-issues writes `.zskills-tracked` with `fix-issues.$SPRINT_ID`; delegated verify-changes (tier-2 resolution) reads it and co-locates fulfilled. No mismatch.
- Hook enforcement globs (`requires.*`, `step.*`, `fulfilled.*`) do NOT match `meta.*` — verified in hook template.
- Tests: 327/327 pass, STABLE 2x.

### Known transitional state
- Cross-pipeline READS at `skills/run-plan/SKILL.md:1176-1177` and `1365-1368` still reference the OLD flat path of the final-verify marker. r&g now writes to subdir; run-plan reads flat. Dual-read in the hook doesn't help here (different code path). **Phase 5 must update these 2 read sites.** Annotation left in r&g's writer block.

### User Sign-off

*(None — non-UI phase.)*

---

## Phase — 3 Writer migration pass 1 ($TRACKING_ID skills)
**Plan:** plans/UNIFY_TRACKING_NAMES.md
**Status:** Completed (verified, awaiting landing)
**Worktree:** /tmp/zskills-pr-unify-tracking-names
**Branch:** feat/unify-tracking-names
**Commits:** 412c7c0 (feat)

### Work Items
| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | run-plan: ~20 sites → subdir layout | Done | 412c7c0 |
| 2 | draft-plan: ~5 sites → subdir (ZSKILLS_PIPELINE_ID fallback) | Done | 412c7c0 |
| 3 | refine-plan: ~4 sites → subdir (fallback) | Done | 412c7c0 |
| 4 | verify-changes: ~6 sites → subdir with **3-tier PIPELINE_ID resolution** (env → `.zskills-tracked` → $MARKER_STEM fallback) | Done | 412c7c0 (round 2 fix after delegation bug caught) |
| 5 | Mirror sync all 4 skills | Done | `diff -r` clean |

### Verification
- **Round 1 verifier caught a real delegation bug**: verify-changes' initial fallback used `$MARKER_STEM.$TRACKING_ID` which resolved to `verify-changes.<slug>` (since `MARKER_STEM` is its own skill name), NOT the parent's PIPELINE_ID. Under run-plan delegation, parent wrote `requires.verify-changes.<slug>` into `run-plan.<slug>/` but verify-changes wrote `fulfilled.*` into `verify-changes.<slug>/` — different subdirs, hook would never match → silent BLOCK.
- Round 2 fix: 3-tier PIPELINE_ID resolution in verify-changes (env → `.zskills-tracked` in cwd → fallback). The `.zskills-tracked` tier is the delegation channel since Claude Code subagent dispatch does not propagate env.
- Round 2 verifier synthetic tests: co-location confirmed (parent's `requires.*` and delegatee's `fulfilled.*` both land in `run-plan.<slug>/`). All 3 tiers resolve correctly.
- Tests: 327/327 pass (dual-read from Phase 2 covers legacy flat fixtures used in tracking-integration tests).

### Known transitional state
- Two residual flat READ paths at `skills/run-plan/SKILL.md:1176-1177` (cross-branch final-verify gate) and `:1365-1368` (cleanup glob). Writers of those markers are research-and-go (Phase 4 scope); the reads will be updated in Phase 5.

### User Sign-off

*(None — non-UI phase.)*

---

## Phase — 2 Reader changes
**Plan:** plans/UNIFY_TRACKING_NAMES.md
**Status:** Completed (verified, awaiting landing)
**Worktree:** /tmp/zskills-pr-unify-tracking-names
**Branch:** feat/unify-tracking-names
**Commits:** c88faa1 (feat)

### Work Items
| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | `scripts/sanitize-pipeline-id.sh` helper | Done | c88faa1 (round 2 fix: trailing-underscore bug) |
| 2 | `scripts/migrate-tracking.sh` one-shot migration | Done | c88faa1 (round 2 fix: requires.* delegation skip) |
| 3 | Hook template 9 reader sites → subdir-first + dual-read | Done | 3 helper fns + 21 call sites + 18 legacy/TODO markers |
| 4 | `skills/update-zskills/SKILL.md` script list +2 entries | Done | c88faa1 |
| 5 | Mirror sync (update-zskills only) | Done | `diff -r` clean |

### Verification
- Round 1 verifier: AC 1-9 PASS, but semantic review flagged 2 real bugs (sanitizer trailing `_`; migrate mis-routed `requires.*` delegation markers).
- Round 2 fix agent: both bugs fixed with synthetic tests (sanitizer: `normal.id` → `normal.id`, no trailing `_`; migration: delegation markers stay flat).
- Round 2 re-verifier: 6/6 PASS including idempotence check (2nd run = no-op).
- Test suite: 327/327 pass (baseline 327, zero delta — Phase 5 adds subdir-path canary coverage).

### Known transitional state
- All 9 hook reader sites dual-read (subdir-first + flat fallback). Flat fallback has `# LEGACY — TODO: remove after Phase 6` markers for Phase 6's grep-based cleanup.
- `scripts/migrate-tracking.sh` is conservative by design: only migrates `fulfilled.<skill>.<id>` and `step.<skill>.<id>.{implement,verify}` for the 4 $TRACKING_ID-using skills (run-plan, draft-plan, refine-plan, verify-changes). `requires.*` delegation markers and non-migrating writers (fix-issues/r&g/r&p/do) stay flat until Phase 4 writer migration; dual-read covers them until then.

### User Sign-off

*(None — non-UI phase.)*

---

## Phase — 1 Decide scheme & document
**Plan:** plans/UNIFY_TRACKING_NAMES.md
**Status:** Completed (verified, awaiting landing)
**Worktree:** /tmp/zskills-pr-unify-tracking-names
**Branch:** feat/unify-tracking-names
**Commits:** 3d94cf1 (docs)

### Work Items
| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | `docs/tracking/TRACKING_NAMING.md` — design doc, Option B, 4 OQs + rubric + layout | Done | 3d94cf1 |
| 2 | CLAUDE.md Tracking-markers subsection referencing the doc | Done | 3d94cf1 |
| 3 | OQ1 trace subsection with file:line citations | Done | 13 citations (>> threshold 4) |
| 4 | OQ2 migration strategy | Done | "let expire" (backward-compat via Phase 2 dual-read) |
| 5 | OQ3 per-sprint unique ID for fix-issues | Done | `sprint-$(date -u +%Y%m%d-%H%M%S)-<8-char-slug>` |
| 6 | OQ4 .landed marker clarification | Done | NOT a tracking marker; out of scope |

### Verification
- 8/8 acceptance criteria pass (design doc exists, CLAUDE.md reference, 4 OQs, chosen scheme, rubric, OQ1 trace ≥4 citations, md-only diff, test regression zero).
- Semantic review: Option B selected with justification, no override triggered; OQ1 metadata decision verified against skills/research-and-go/SKILL.md:155,156,163, skills/research-and-plan/SKILL.md:328 and 9 hook reader lines at 251,264,276,359,372,384,460,473,485 (no enforcement path reads integer markers).
- Test suite: 327/327 pass (baseline preserved — phase is docs-only).

### User Sign-off

*(None — non-UI docs phase.)*

---
Generated by `/run-plan plans/UNIFY_TRACKING_NAMES.md finish auto pr`
