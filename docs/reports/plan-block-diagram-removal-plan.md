# Plan Report — Block-Diagram Add-On Removal

## Phase — 2 Delete the trees + deletion-coupled edits

**Plan:** docs/plans/BLOCK_DIAGRAM_REMOVAL_PLAN.md
**Status:** Completed (verified)
**Commits:** 30c097d3 (impl+verify, 14 D + 8 M)

### Work Items
block-diagram/ tree (incl. zsbd manifest + screenshots), docs/skills/block-diagram/, both installed mirrors (model-design had none), 2 smoke suites + run-all registrations deleted; plugin.json skills → ["./skills/"] (no hooks field); .gitignore unignore rules dropped; test-plugin-manifest zs-only rewrite (skills assertion TIGHTENED to exact equality); frontmatter-survival + mirror-parity reworked; conformance mirror-source fallback deleted; CI fatal tier-2 zsbd validate block deleted (comments survive for Phase 3 F).

### Verification
- Verifier PASS (independent), committed 30c097d3; Layer-3 validate exit 0.
- Suite: Overall: 7617/7617 passed, 0 failed. Drop −41 vs post-Phase-1 baseline independently recomputed per-suite (smoke −7/−10, manifest −15, conformance −2, survival −1, parity −6) — exact. Weakening audit CLEAN. DocsRegistry byte-identical after regen.
- Drift: 1 advisory — AC3 grep expects 0 hits but 1 comment-only hit at test.yml:143 is owned by Phase 3 F per the plan itself; self-resolves next phase. Fork note: rescope AC3 to executable lines.

### User Sign-off
(No UI files changed — omitted.)

## Phase — 1 De-reference the test layer

**Plan:** docs/plans/BLOCK_DIAGRAM_REMOVAL_PLAN.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-block-diagram-removal-plan (branch feat/block-diagram-removal-plan)
**Commits:** f4479288 (impl, 19 test files, +145/−377), 56f3a0e8 (tracker)

### Work Items
All Phase 1 items done in one change set: conformance single-touch (presence entry, check_fixed ×2, scan-root narrowing w/ floor 6 KEPT, #458 tripwire deleted, 9 scanner roots narrowed — one more than the plan's 8, found by content per plan instruction), invariants (meta-lint + exempt machinery deleted, Phase C 4→3, sibling count check), forbidden-literals dual-root, marketplace zsbd+D10 deleted w/ replacement zs-version assertion, self-load/live-load zsbd halves, version-delta tree-coupled (floors 7→5, 26→23 re-derived), version-surface element-level (Test 4 core + $T4 kept), lane-aware AC5c only, canary 9–11 + rewrite-marketplace + delegate-skip RENAMED (coverage preserved), cosmetic narrowings ×5 files.

### Verification
- Verifier: PASS (independent), committed f4479288. Layer-3 validate: exit 0.
- Test suite: `bash tests/run-all.sh` → **Overall: 7658/7658 passed, 0 failed** (115 suite blocks, parity with baseline). Baseline (main): 7686/7687, 1 failed (pre-existing load-sensitive `test_p95_under_budget`; passed this run). Count drop of 29 fully accounted per-suite (incl. 4 attended live-load cases that SKIP headless — environmental, not deletions).
- Tests-never-weakened audit: CLEAN (all subject-removal or honest re-derivation).
- Do-NOT-touch survivors intact: conformance mirror-source fallback, refuse_gate ADDON_FLAG, smoke tests + registrations, plugin-manifest/frontmatter-survival/mirror-parity/mirror-skill T9/enforcement case 19.

### Fork-portability notes (drift log)
- PLAN-TEXT-DRIFT (advisory, non-derivable): scanner-root sites 8 enumerated → 9 actual (prose-imperative coverage scan at old ≈L3342); drift-extended-scope "assertion inverts" → actually only an unused fixture element + comment.
- Line refs moved: #458 tripwire L2083–2114 (plan ≈L2060–2113); meta-lint L463–535 (≈L464–534); fallback now L3162–3165 post-edit.
- Interpretations: version-enforcement = ZERO Phase-1 edits (header/body tension resolved via AC survivors list); description-budget had 2 extra literals (L3 header, L39 model-design) — cleaned, required by AC grep.
- Environment: attended live-load cases inflate authed baselines by ≤4 passes vs headless runs — classify as environmental in count accounting.

### User Sign-off
(No UI files changed — omitted.)
