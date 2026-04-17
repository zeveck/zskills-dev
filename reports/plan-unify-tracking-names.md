# Plan Report — UNIFY_TRACKING_NAMES

Plan: `plans/UNIFY_TRACKING_NAMES.md`

## Phase — 3 Writer migration pass 1 ($TRACKING_ID skills) [UNFINALIZED]

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

## Phase — 2 Reader changes [UNFINALIZED]

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

## Phase — 1 Decide scheme & document [UNFINALIZED]

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
