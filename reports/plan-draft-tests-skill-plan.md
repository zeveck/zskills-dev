# Plan Report — /draft-tests Skill

## Phase — 5 Backfill mechanics and re-invocation [UNFINALIZED]

**Plan:** plans/DRAFT_TESTS_SKILL_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-draft-tests-skill-plan
**Branch:** feat/draft-tests-skill-plan
**Commits:** 56df394

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 5.1 | Three-level gap-detection rubric (COVERED / UNKNOWN / MISSING) — backticked-token-required for MISSING; prose-only never triggers | Done | 56df394 |
| 5.2 | Backfill phase append at correct structural position (broad-form heading rule, fenced-code-block aware) — closed-enumeration regression guard | Done | 56df394 |
| 5.3 | Backfill phase content (Goal / Work Items / D&C / AC / Dependencies) | Done | 56df394 |
| 5.3b | Update parsed-state on backfill — append to `non_delegate_pending_phases:` so Phase 4's coverage-floor pre-check enforces the floor on backfill ACs | Done | 56df394 |
| 5.4 | Cluster 1–3 Completed phases per backfill phase (no mega-phase on 4+ MISSING) | Done | 56df394 |
| 5.5 | Re-invocation detection — existing `### Tests` becomes round-0 draft | Done | 56df394 |
| 5.6 | Frontmatter flip `status: complete` → `active` ONLY when appending backfill (single-purpose) | Done | 56df394 |
| 5.7 | `## Test Spec Revisions` 2-column section, placed AFTER `## Drift Log` / `## Plan Review` (closes /refine-plan checksum-boundary cross-skill interaction) | Done | 56df394 |
| 5.8 | Completed-phase checksum drift gate — STOP with error, plan NOT written | Done | 56df394 |

### Verification
- Test suite: **1652/1652 passed, 0 failed** (baseline 1549; +103 net new in `tests/test-draft-tests-phase5.sh` — verifier added one strengthening assertion to AC-5.1's no-op branch).
- Per-AC verification (AC-5.1 through AC-5.11): all PASS, independently re-checked by a fresh verifier.
- **Verifier-found bug, fixed before push:** `append-backfill-phase.sh` no-op branch tripped `set -u` because `declare -a MISSING_PIDS` (no `=()`) left the array unset. Plan file was untouched (defensive abort), but script exited 1 instead of 0 on the no-MISSING path; impl agent's AC-5.1 test had masked this with `2>/dev/null` and an exit-code-agnostic assertion. Verifier fixed the script (`declare -a MISSING_PIDS=()`), strengthened the test to assert exit code 0, regenerated the Tier-1 hash, and re-mirrored.
- **AC-5.7 (load-bearing) deep-dive:** verifier confirmed the broad-form section-boundary rule against the `non-canonical-trailing.md` fixture (`## Anti-Patterns -- Hard Constraints` between last phase and `## Plan Quality`). Backfill landed IMMEDIATELY BEFORE `## Anti-Patterns`; bytes byte-identical pre/post via `diff`. Fenced-code-block regression: ` ```markdown ` block containing `## Example` at column 0 was correctly skipped; backfill landed before `## Plan Quality`, not the in-fence heading.
- **AC-5.10 (data-flow) deep-dive:** verifier traced the end-to-end path — pre-backfill parsed-state had `non_delegate_pending_phases:` empty; after `append-backfill-phase.sh` ran, parsed-state contained the backfill phase ID; running `coverage-floor-precheck.sh` (Phase 4) against post-5.3b state synthesized `Coverage floor violated: AC-2.1 ...` for the backfill phase's missing AC. Single-source-of-truth invariant intact.
- AC-5.11 placement: `## Drift Log` → `## Plan Review` → `## Test Spec Revisions` → `## Plan Quality` order verified.
- AC-5.8 frontmatter: both branches verified (with-backfill flips `status:`; without leaves byte-identical).
- AC-5.9 checksum: tampered Completed-phase body causes `verify-completed-checksums.sh` to exit 1, name the drifted phase, and leave the plan-file mtime preserved.
- Tier-1 hash integrity: all 6 new scripts have actual `git hash-object` recorded (post-bugfix hash for `append-backfill-phase.sh`).
- Source/mirror parity: clean.

### Implementation notes
- 6 new scripts: `gap-detect.sh`, `append-backfill-phase.sh`, `insert-test-spec-revisions.sh`, `flip-frontmatter-status.sh`, `re-invocation-detect.sh`, `verify-completed-checksums.sh`.
- 10 new fixtures under `tests/fixtures/draft-tests/p5/` covering all 11 ACs.
- Tier-1 ownership total now 29 entries (Phase 5 added 6).
- mawk-portable awk throughout; verifier-strengthened test ensures regressions on the no-op branch are caught (no more masked `set -u` failures).

## Phase — 4 Adversarial review loop (QE personas)

**Plan:** plans/DRAFT_TESTS_SKILL_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-draft-tests-skill-plan
**Branch:** feat/draft-tests-skill-plan
**Commits:** c9ebf31

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 4.1 | Reviewer agent prompt with senior-QE persona + finding categories + guidance prepend | Done | c9ebf31 |
| 4.2 | Devil's-advocate prompt — adversarial stance, calibrated against gotcha generation | Done | c9ebf31 |
| 4.3 | NOT-a-finding list (authored fresh — Bach/Bolton/Beck-cited) verbatim in both prompts | Done | c9ebf31 |
| 4.4 | Zero findings is valid — explicit `## Findings` "No findings" path in output-format block | Done | c9ebf31 |
| 4.5 | Mandatory `Blast radius:` line on every finding; minor dropped, moderate/major must resolve | Done | c9ebf31 |
| 4.6 | Prior-rounds dedup (round 2+ feeds previous findings as "already addressed"); refiner secondary gate | Done | c9ebf31 |
| 4.7 | Evidence discipline — `Verification:` line on every empirical claim (mirrors /draft-plan PR #71) | Done | c9ebf31 |
| 4.8 | Orchestrator-level coverage-floor pre-check on per-round MERGED candidate file (closes first/re/backfill ambiguity) | Done | c9ebf31 |
| 4.9 | Refiner with verify-before-fix + disposition table; refiner does NOT declare convergence | Done | c9ebf31 |
| 4.10 | Per-round artifacts: review-round-N + refined-round-N files | Done | c9ebf31 |
| 4.11 | Convergence check via orchestrator (NOT refiner self-call) — 4 positive conditions | Done | c9ebf31 |

### Verification
- Test suite: **1549/1549 passed, 0 failed** (baseline 1470; +79 new in `tests/test-draft-tests-phase4.sh`).
- Per-AC verification (AC-4.1 through AC-4.9): all PASS, independently re-checked by a fresh verifier.
- **AC-4.9 (load-bearing) deep-dive:** verifier read `convergence-check.sh` source — confirmed it never short-circuits on refiner prose claims; the awk-based parser walks the disposition table mechanically. Run against the `refiner-falsely-claims-converged.md` fixture (which contains "CONVERGED" + "No further refinement needed" prose with 2 unresolved Justified rows): rc=1, NOT CONVERGED — orchestrator correctly overrides refiner self-call. CLAUDE.md memory `feedback_convergence_orchestrator_judgment.md` upheld.
- AC-4.5 (no live LLM in tests): verifier confirmed zero `Agent(`/`claude`/`ANTHROPIC_API` matches in test logic; 21 stub env-var references confirm everything goes through `ZSKILLS_DRAFT_TESTS_*_STUB_<N>` env vars. Live mode gated behind `ZSKILLS_TEST_LLM=1`.
- Tier-1 hash integrity: all 3 new scripts have actual `git hash-object` recorded (verifier ran `git hash-object` and grepped tier1-shipped-hashes.txt for each).
- Source/mirror parity: clean.
- Plan-text drift: zero tokens (Phase 4 spec explicitly out-of-scope for PLAN-TEXT-DRIFT per Design & Constraints).

### Implementation notes
- 3 new scripts: `review-loop.sh` (round driver), `coverage-floor-precheck.sh` (operates on the merged candidate at `/tmp/draft-tests-candidate-round-N-<slug>.md`), `convergence-check.sh` (4-condition mechanical orchestrator judgment, ignores refiner prose).
- Exit codes: 0 = converged, 2 = max rounds + floor unmet (partial-success), 3 = max rounds + floor met but other unresolved findings, 6 = no stubs and no `ZSKILLS_TEST_LLM=1` (fail-loud).
- Coverage floor uses awk-portable `match() + RSTART/RLENGTH + substr()` (mawk-safe); first attempt used 3-arg `match($0, regex, m)` which is gawk-only and silently failed on mawk — caught by AC-4.8 pre-merge test.
- Tier-1 ownership now 23 entries (Phase 4 added 3); STALE_LIST kept in sync; tier1-shipped-hashes.txt updated with **actual** hashes after final edits.
- Implementer self-caught one stale hash mid-run (re-edited script after registering hash; re-registered with the post-edit `git hash-object`). Phase 2's stale-hash defect did not regress.

## Phase — 3 Drafting agent and test-spec format

**Plan:** plans/DRAFT_TESTS_SKILL_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-draft-tests-skill-plan
**Branch:** feat/draft-tests-skill-plan
**Commits:** b1b8906

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 3.1 | One-line spec format (`- [scope] [risk: AC-N.M] given <input>, when <action>, expect <literal>`) | Done | b1b8906 |
| 3.2 | Multi-line expansion (Input/Action/Expected/Rationale sub-bullets) | Done | b1b8906 |
| 3.3 | Drafting agent prompt with senior-QE persona + research-cited calibration cues | Done | b1b8906 |
| 3.4 | Drafter inputs: full plan, parsed-state path, research path, resolved test-cmd context, calibration outputs | Done | b1b8906 |
| 3.5 | Append logic with position priority (AC → D&C → Work Items; never before Goal, never inside Execution) + idempotent re-invocation | Done | b1b8906 |
| 3.6 | Skip delegate phases per parsed-state `delegate_phases:` (single-source-of-truth, no plan-body re-greping); record `delegate_skipped_phases:` artifact | Done | b1b8906 |
| 3.7 | Calibrate to existing project test conventions (Phase 2 calibration signal) | Done | b1b8906 |
| 3.8 | Drafter output written to `/tmp/draft-tests-draft-round-0-<slug>.md` for Phase 4's review loop | Done | b1b8906 |

### Verification
- Test suite: **1470/1470 passed, 0 failed** (baseline 1406; +64 new in `tests/test-draft-tests-phase3.sh`).
- Per-AC verification (AC-3.1 through AC-3.6): all PASS, independently re-checked by a fresh verifier.
- AC-3.6 single-source-of-truth: verifier mutated the plan body (removed `### Execution: delegate` line) AFTER parsing and confirmed orchestrator still skipped the delegate phase — proves parsed-state is authoritative, not a re-grep heuristic.
- AC-3.5 idempotency: verifier ran orchestrator twice on same fixture; `cmp -s` clean; no duplicate or nested `### Tests`.
- Tier-1 hash integrity: both new scripts have actual `git hash-object` recorded in `tier1-shipped-hashes.txt` (the Phase 2 stale-hash defect did not regress).
- Source/mirror parity: `diff -rq skills/draft-tests/ .claude/skills/draft-tests/` clean.
- Plan-text drift: zero `PLAN-TEXT-DRIFT:` tokens. AC-3.1's `N − K` formula (4-1=3) self-passes against the n-minus-k fixture.

### Implementation notes
- Two new scripts: `append-tests-section.sh` (mechanical position-priority insertion, fenced-code-block-aware boundary scan, byte-preserving) and `draft-orchestrator.sh` (parsed-state consumer + per-round output writer with `drafted_phases`/`delegate_skipped_phases`/`ac_less_skipped_phases`/`idempotent_skipped_phases` artifacts).
- Orchestrator is parameterized with a SPECS FILE (the drafter agent's output) so tests stub the agent by writing the file directly — no live LLM dispatch in tests, matching the AC-4.5 pattern that Phase 4 will extend.
- Tier-1 ownership: now 20 entries in `script-ownership.md` (Phase 1 added 1, Phase 2 added 2, Phase 3 added 2).
- 4 new fixtures (`n-minus-k.md`, `delegate-skip.md`, `idempotency.md`, `regex-conformance.md`) cover the load-bearing behaviors. The regex-conformance fixture exercises sub-letter ACs (`AC-1.6c`) for AC-3.2's grammar.

## Phase — 2 Language detection, test-file discovery, no-test-setup path

**Plan:** plans/DRAFT_TESTS_SKILL_PLAN.md
**Status:** Completed (verified) — landed via PR squash merge
**Worktree:** /tmp/zskills-pr-draft-tests-skill-plan
**Branch:** feat/draft-tests-skill-plan
**Commits:** e7b4d66, e415499 (post-rebase: was 4ec3bc4, ff33eea)

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 2.1 | Language detection from manifest files (JS/TS, Python, Go, Rust, Bash, polyglot, none) with per-language runner recommendations | Done | 4ec3bc4 |
| 2.2 | Test-file discovery via per-language heuristics (NOT runner-sniffing) | Done | 4ec3bc4 |
| 2.3 | Bounded calibration signal: ≤ 3 files, ≤ 20 lines per language; persisted full path list (not contents) for Phase 5 reuse | Done | 4ec3bc4 |
| 2.4 | No-test-setup `## Prerequisites` block insertion between Overview and Progress Tracker (byte-preserving) | Done | 4ec3bc4 |
| 2.5 | `--bootstrap` flag explicitly OUT of scope; recommendation text is the entire no-test-setup behavior | Done | 4ec3bc4 (documented in SKILL.md) |
| 2.6 | Config-first three-case test-cmd resolution (mirror `/verify-changes` lines 76–137) — no runner-sniffing | Done | 4ec3bc4 |
| 2.7 | Graceful fallback on detection error (stderr log, "language undetectable", rc=0) | Done | 4ec3bc4 |
| Tier-1 hash correction follow-up | Replaced two stale entries in `tier1-shipped-hashes.txt` with actual `git hash-object` output (verifier-flagged) | Done | ff33eea |

### Verification
- Test suite: **1387/1387 passed, 0 failed** (baseline 1334/1334; +53 new in `tests/test-draft-tests-phase2.sh`).
- Per-AC verification (AC-2.1 through AC-2.10): all PASS, independently re-checked by a fresh verifier against fixture data.
- AC-2.10 byte-preservation regression: load-bearing — verifier ran `cmp -s` on every level-2 section before/after `insert-prerequisites.sh`, including non-canonical trailing headings (`## Anti-Patterns -- Hard Constraints`, `## Non-Goals`, `## Risks and Mitigations`). All byte-identical.
- Source/mirror parity: `diff -rq skills/draft-tests/ .claude/skills/draft-tests/` clean.
- Conformance suite: clean (new bash fences in SKILL.md added zero unguarded forbidden literals).
- Migration test (case 6c commit-cohabitation): PASS — actual hashes for both new scripts now in tier1-shipped-hashes.txt.
- Plan-text drift: zero `PLAN-TEXT-DRIFT:` tokens from either implementation or verification agent. Numeric AC bands (≥ 4 / ≤ 3 / ≤ 20) verified against fixture.

### Implementation notes
- Two new mechanical scripts: `detect-language.sh` (manifest-only language detection + bounded calibration signal extraction; bash-regex JSON parsing, no jq) and `insert-prerequisites.sh` (idempotent in-place insertion with fenced-code-block-aware section-boundary scan, mirroring Phase 1's parser).
- Both scripts registered Tier 1 in `script-ownership.md` (now 18 entries) + STALE_LIST in `update-zskills/SKILL.md` + actual blob hashes in `tier1-shipped-hashes.txt`.
- 9 new fixtures under `tests/fixtures/draft-tests/p2/`: language-only (`js-only`, `py-only`, `polyglot-go-js`, `no-manifest`), behavioral (`existing-js-tests`, `malformed-manifest`, `config-set`, `no-test-setup`), and the AC-2.10 regression guard `prereq-trailing` with three non-canonical trailing headings.
- The verifier's stale-hash defect was a real one — flagged but not test-caught (case 6b checks format only, case 6c checks temporal ordering); fixed in `ff33eea` before push.

## Phase — 1 Skeleton, ingestion, and checksum gate

**Plan:** plans/DRAFT_TESTS_SKILL_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-draft-tests-skill-plan
**Branch:** feat/draft-tests-skill-plan
**Commits:** 2cf6897, 5201b8e

### Work Items

| # | Item | Status | Commit |
|---|------|--------|--------|
| 1.1 | `skills/draft-tests/SKILL.md` with frontmatter (`name`, `disable-model-invocation`, `argument-hint` incl. `[guidance...]`, description) | Done | 2cf6897 |
| 1.2 | Argument parsing: plan-file detection, `rounds N`, guidance text join with usage-string error | Done | 2cf6897 |
| 1.3 | Tracking fulfillment via canonical idiom + per-pipeline subdir + cross-skill `sanitize-pipeline-id.sh` form (bare-relative form refused) | Done | 2cf6897 |
| 1.4 | Plan-file parser: frontmatter, Progress Tracker, phase classification (Done/✅/[x] vs Pending) | Done | 2cf6897 |
| 1.4b | Per-Pending-phase delegate vs non-delegate predicate; `delegate_phases:` and `non_delegate_pending_phases:` lists in parsed-state | Done | 2cf6897 |
| 1.5 | SHA-256 checksum per Completed phase with broad-form section-boundary rule (any `## <name>` outside fenced code blocks) AND fenced-code-block awareness | Done | 2cf6897 |
| 1.6 | AC-ID assignment with three-predicate classifier (canonical-skip, ambiguous-refuse-with-advisory, plain-assign) | Done | 2cf6897 |
| 1.7b | Pending phases without `### Acceptance Criteria` block recorded in `ac_less:` and retained in `non_delegate_pending_phases:`, advisory emitted | Done | 2cf6897 |
| 1.7 | Refuse-to-run checks: missing plan / missing tracker → error; all-Completed → continue (route to backfill, not exit) | Done | 2cf6897 |

### Verification
- Test suite: **1275/1275 passed, 0 failed** (baseline 1213/1213; +62 new tests in `tests/test-draft-tests.sh`).
- Per-AC verification (AC-1.1 through AC-1.7b): all PASS, independently re-checked by a fresh verification agent against fixture plans.
- Source/mirror parity: `diff -rq skills/draft-tests/ .claude/skills/draft-tests/` clean.
- Conformance suite: 170/170; invariants suite: 36/36.
- Plan-text drift: zero `PLAN-TEXT-DRIFT:` tokens from either implementation or verification agent.

### Implementation notes
- `parse-plan.sh` factored under `skills/draft-tests/scripts/` because Phase 1's mechanics (parse, classify, checksum, AC-ID, ac-less detection) are far more deterministic than `/refine-plan`'s prose-only architecture. Registered Tier 1 in `skills/update-zskills/references/script-ownership.md` (16 entries) and added to `STALE_LIST` in `update-zskills/SKILL.md` so consumer checkouts will not retain bare-relative copies.
- 7 fixture plans under `tests/fixtures/draft-tests/` cover mixed-status, trailing-sections, fenced-headings, ambiguous-prefixes, all-completed, ac-less-and-normal, and no-tracker scenarios.
- The fenced-code-block-aware section-boundary scan is the load-bearing checksum invariant; the regression fixture `fenced-headings.md` proves the awk-style state-tracker correctly skips `## ` headings inside ` ``` ` fences and includes the fenced bytes in the checksummed span.
- Phases 2–6 are stubbed in SKILL.md with deferral notes; the architectural hooks for Phase 3's `### Tests` skip on `ac_less:` phases and Phase 4's coverage-floor exclusion of ac-less phases are documented inline so downstream phases can wire to the single source of truth.
