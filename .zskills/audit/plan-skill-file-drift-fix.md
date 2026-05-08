# Plan Report — Skill-File Drift Fix

## Phase — 5 Verification + Drift-Regression Test (FINAL)

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** (pending verifier squash)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 5.1 | Inline /verify-changes scope review | Done | 14 commits cumulative on `feat/skill-file-drift-fix`; 67 files / +2812 / -298 vs `dev/main`. Every changed file maps to a plan WI. Mirror parity clean across the 4 Phase-5 source skill edits. No off-scope creep. Full test suite passes (1272/1272). |
| 5.2 | Two-sided drift-regression test (positive side) | Done | `tests/test-skill-conformance.sh` gains a fence-local positive-side scanner (`scan_positive_side`). Recognizes 3 legitimate equivalents to helper-source preamble: (a) explicit `. zskills-resolve-config.sh`, (b) inline self-resolution (`CONFIG_CONTENT=$(cat ...)` + BASH_REMATCH), (c) blockquoted recipes governed by substitution-discipline at `skills/run-plan/SKILL.md:179-187`. 2 synthetic fixtures (PASS, FAIL) + 1 real-tree pass. **Surfaced 3 Phase-2 misses → fixed**: helper-source preamble added at `skills/run-plan/SKILL.md:1067` (test-baseline fence), `skills/quickfix/SKILL.md:623` (commit-body fence using `$COMMIT_CO_AUTHOR`), `skills/run-plan/modes/pr.md:429` (CI fix-cycle fence with agent-prompt comments referencing `$FULL_TEST_CMD`/`$TEST_OUTPUT_FILE`). |
| 5.3 | DRIFT_ARCH_FIX cross-reference | Done | One-line "see also" pointer appended to `plans/DRIFT_ARCH_FIX.md` immediately after Plan Quality bullets, before Round History. |
| 5.4 | PLAN_INDEX.md update | Done | SKILL_FILE_DRIFT_FIX moved from "Ready to Run" to "Complete" (`6 phases — All phases done; landed 2026-04-29`). Totals updated: `7 ready → 6 ready, 16 complete → 17 complete`. |
| 5.5 | Rule paragraph in CLAUDE_TEMPLATE.md | Done | `.claude/rules/zskills/managed.md` does not exist; CLAUDE_TEMPLATE.md is the canonical source (it renders into managed.md). New "Resolution rule." paragraph added under existing "Skill-file hardcode discipline" heading; documents helper-source MUST + inline self-resolution / blockquote substitution-discipline equivalents. |
| 5.6 | Live blockquote-emission smoke (manual) | Documented | Recipe in "Manual smoke recipe" subsection below; not mechanically testable from outside an orchestrator session. |
| 5.7 | PROSE-IMPERATIVE substitution-discipline coverage | Done (Option A) | Per-site grep loop in `tests/test-skill-conformance.sh`. Detector: bullet/numbered + code-span + `$FULL_TEST_CMD\|$DEV_SERVER_CMD`, outside fences and outside blockquotes (the latter governed by substitution-discipline). Window check: ±5 lines for `zskills-resolve-config.sh` OR `CONFIG_CONTENT=$(cat` OR `(resolved from config` OR `(resolve via`. Scans 10 sites; all pass. **Option A applied**: 3 inline annotations added (`run-plan/SKILL.md:1148`, `verify-changes/SKILL.md:130`, `verify-changes/SKILL.md:504`) — 1-2 lines per site. The 9 PROSE-IMPERATIVE-migrated sites enumerated in the plan already had `(resolve via ... zskills-resolve-config.sh ...)` annotations from Phase 2; the 3 fix-ups close additional bullet-form $VAR references the broader detector found. |

### Verification

- **Test suite:** PASSED (1268 baseline → 1272 after Phase 5, **+4 cases**, 0 failures). New cases: 1 synthetic-PASS positive-side, 1 synthetic-FAIL positive-side, 1 real-tree positive-side, 1 PROSE-IMPERATIVE coverage.
- **Positive-side real-tree:** every fence in `skills/` that references one of `{UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, DEV_SERVER_CMD, TEST_OUTPUT_FILE, COMMIT_CO_AUTHOR}` either sources `zskills-resolve-config.sh`, performs inline self-resolution, or is a blockquoted recipe governed by substitution-discipline.
- **PROSE-IMPERATIVE coverage:** 10 of 10 bullet/numbered $VAR sites have nearby resolution-discipline annotation.
- **Mirror parity:** `diff -q` clean across all 4 Phase-5 source/mirror pairs.
- **No PROSE refs flagged outside fences:** the substitution-discipline annotation at `skills/run-plan/SKILL.md:181` ("the orchestrator substitutes `$FULL_TEST_CMD`") is correctly NOT a positive-side consumer (fence-local check ignores prose).
- **Frontmatter:** `status: complete`, `completed: 2026-04-29` written; tracker row 5 marked ✅ Done.

### Manual smoke recipe (WI 5.6 — blockquote emission)

The blockquote-substitution discipline is model-side (not bash-mechanical). The structural AC at WI 4.6 + the deny-list at 4.1 catch the markdown-source surface, but they cannot verify that the orchestrator-model actually substitutes `$DEV_SERVER_CMD` / `$TEST_OUTPUT_FILE` literals before emission to a dispatched subagent. Recipe:

1. Configure a fixture project with `.claude/zskills-config.json` containing `dev_server.cmd: "yarn start"` and `testing.output_file: ".out.log"`.
2. Run `/run-plan plans/<any>.md 1` to dispatch an implementation worktree-test cycle.
3. Inspect the dispatched subagent's prompt (via the standard subagent-prompt-capture pattern in `tests/run-all.sh` if available, or via /run-plan's tracking markers / report).
4. Assert the prompt contains literal `yarn start &` and `$TEST_OUT/.out.log`, NOT `$DEV_SERVER_CMD &` or `$TEST_OUT/$TEST_OUTPUT_FILE` (literal-unresolved means the model failed the discipline).

Standard tracking markers do not currently expose dispatch-prompt content, so this is a manual one-time smoke per release. Documented for future regression coverage.

### Design deviations (verified SOUND)

1. **Positive-side check accepts inline self-resolution + blockquote.** The spec pseudocode showed only the `zskills-resolve-config.sh` helper-source preamble. Implementation added two equivalents: (a) inline `CONFIG_CONTENT=$(cat ...)` + `BASH_REMATCH` (a fence that DEFINES the var by reading config inline — circular to require helper-source), (b) blockquoted fences (`> `-prefixed) governed by the substitution-discipline annotation, not by helper-source. Without these equivalents, the resolution-defining fences at `run-plan/SKILL.md:144` and `verify-changes/SKILL.md:82` would self-flag, and the worktree-test recipe blockquote would self-flag despite the explicit substitution-discipline.

2. **PROSE-IMPERATIVE coverage detector relaxed (no imperative-verb gate).** The deny-list's PROSE-IMPERATIVE detector requires a sentence-start imperative verb (`Run`/`Execute`/`Invoke`) to avoid false-positives on bare literals like "has run". The COVERAGE check here is broader: bullet/numbered + code-span + $VAR — because Phase 2's migration introduced annotation-bearing prose forms that don't always carry an imperative verb (e.g., `- \`$FULL_TEST_CMD\` (resolve via ...)`). The window check is the discriminator that prevents false-positives.

3. **Coverage window markers expanded beyond `zskills-resolve-config.sh` literal.** Added recognition of `(resolved from config`, `(resolve via`, and `CONFIG_CONTENT=$(cat` as legitimate annotations within ±5 lines. Reflects what Phase 2 actually shipped; without this, sites whose annotation pointed to an in-skill resolution section (rather than the helper directly) would falsely flag.

### Plan-Text Drift

`bullet=5.2 field=positive-side-equivalents plan=helper-source-only actual=helper-source-OR-inline-self-resolution-OR-blockquoted` — see Design deviation 1 above. Plan said the test should fail when "the canonical block is missing"; implementation interprets canonical block to include all 3 functionally-equivalent resolution patterns documented in `references/canonical-config-prelude.md` (helper source + inline self-resolution per the existing `skills/run-plan/modes/pr.md:325-345` convention) and the substitution-discipline at `skills/run-plan/SKILL.md:179-187` (for blockquotes).

`bullet=5.7 field=detector-form plan=PROSE-IMPERATIVE-only actual=bullet+codespan+\$VAR` — see Design deviation 2 above. Plan referenced "PROSE-IMPERATIVE-migrated sites" by deny-list detector terminology; coverage check is broader because Phase 2's migrated forms are not all imperative-verb sentences.

### User Sign-off

Phase 5 produces no UI changes — no sign-off needed.

## Phase — 4 Enforcement (deny-list + drift-warn + allowlist)

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** f26fac3

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.1 | Test deny-list (test-skill-conformance.sh) | Done | +201 lines; fence-state tracker upgraded to handle ALL fence languages (refines spec pseudocode); strips `>` blockquote-prefix; PROSE-IMPERATIVE detection; `re:` prefix dispatch |
| 4.2 | Drift-warn hook extension | Done | +104 lines (template + mirror); skill-file matcher anchored to exclude `.claude/skills/` mirrors; reads same fixture as 4.1 |
| 4.3 | Settings.json wiring | Done (NO CHANGE) | Existing Edit\|Write matcher already wires warn-config-drift.sh per refine-2 DA2.6 |
| 4.4 | Allowlist convention | Done | CLAUDE_TEMPLATE.md +35 lines; 3 worked examples; managed.md is render output (template is canonical) |
| 4.5 | Test cases for WI 4.2 | Done | +181 lines; 5 skill-file branch + 2 fixture-extension single-source-of-truth tests |
| 4.6 | Blockquote-structural AC | Done | In test-skill-conformance.sh; asserts INJECTED-BLOCKQUOTE contains only `$VAR` refs; substitution-discipline names all 3 vars |
| 4.7 | Phase ordering split | Done | Deny-list passes against post-Phase-2 baseline; 2 surfaced drift sites markered (do/SKILL.md:401 npm-test report-template, update-zskills/SKILL.md:613 npm-start render-report) |

### Verification

- **Test suite:** PASSED (1258 baseline → 1268 after Phase 4, +10 cases, 0 failures)
- **Mirror parity:** clean (`diff -q hooks/warn-config-drift.sh .claude/hooks/warn-config-drift.sh` empty)
- **Allowlist markers well-formed:** both reference literal verbatim with one-line `reason:` field
- **Fence-tracker upgrade:** verified empirically; `verify-changes/SKILL.md` has 5 ```markdown fences whose closers would have corrupted spec's tracker

### Design deviations (verified SOUND)

1. **Fence-tracker tracks all languages, scans only exec.** Spec pseudocode's regex `^[[:space:]]*\`\`\`(bash|sh|shell)?[[:space:]]*$` would not match `\`\`\`markdown` etc. but would treat closer as opener — corrupting fence state. Implementer's upgrade (track all, scan exec) is the correct fix.

2. **Allowlist convention in CLAUDE_TEMPLATE.md not managed.md directly.** `managed.md` does not exist in the repo; it's generated from `CLAUDE_TEMPLATE.md` by `/update-zskills --rerender`. Template is the only valid source-of-truth location.

### Plan-Text Drift

`bullet=4.1 field=fence-state-tracker plan=bash-only-opener actual=any-language-opener-with-exec-vs-other-classification` — pseudocode upgrade documented above.

### User Sign-off

Phase 4 produces no UI changes — no sign-off needed.

## Phase — 3 Hook Fallback Fix + Test-Infra Sync

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** 4311f42

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | Sweep `${VAR:-default}` opinionated fallbacks | Done | 26 hits audited; 1 opinionated FIXED (FULL_TEST_CMD npm fallback); 25 sensible KEPT (env-overridable plumbing + new doc-defaults) |
| 3.2 | Implement three-case tree | Done | Case A (cmd set), Case B (empty + no infra → skip), Case C (empty + infra → deny test-pipes) |
| 3.3 | Mirror to .claude/hooks/ | Done | diff -q empty |
| 3.4 | Test-infra sync via shared fixture | Done | tests/fixtures/test-infra-patterns.txt (9 patterns); sync test in test-hooks.sh checks both consumers |
| 3.5 | Three test cases for WI 3.2 | Done | 5 cases (Case A + Case A output_file honored + Case B + Case C deny + Case C non-test allow); 4 sync tests |

### Design deviation: helper-vs-inline (verified SOUND)

The plan's WI 3.1 prescribed sourcing `zskills-resolve-config.sh` for the suggestion-message text. Implementer chose inline config-read instead. Rationale:
- Helper has hard fail-loud `${CLAUDE_PROJECT_DIR:?...}` guard.
- Test fixtures use `REPO_ROOT=$TEST_TMPDIR` without setting `CLAUDE_PROJECT_DIR` — sourcing helper would abort fixtures.
- Inline implementation is contractually equivalent (same BASH_REMATCH idiom, empty-init guard, malformed-tolerance, no-jq).
- Case A `output_file` test proves equivalence: configured `.out.log` appears in deny message; literal `.test-results.txt` absent.

Verifier judged SOUND. Future cleanup that exports `CLAUDE_PROJECT_DIR` in fixtures + switches hook to helper-source is a sensible follow-up but not in scope.

### Verification

- **Test suite:** PASSED (1249 baseline → 1258 after Phase 3, +9 cases, 0 failures)
- **AC 1** (zero `:-npm run test:all`): 0 hits in `hooks/` and `.claude/hooks/`
- **AC 2** (three test cases): 5 present (Case A, A-output_file, B, C, C-allow)
- **AC 3** (sync test): present + synthetic-divergence message format check
- **AC 4** (full suite passes): 1258/1258
- **Mirror parity:** clean (`diff -q hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh` empty)
- **Pattern parity:** all 9 patterns appear in both `block-unsafe-project.sh` and `verify-changes/SKILL.md`

### Plan-Text Drift

None observed. Implementer's `${VAR:-default}` count was 24; verifier counted 26 (the 2 extras are the new `${TEST_OUTPUT_FILE:-.test-results.txt}` doc-defaults — sensible additions, not pre-existing audit items). Cosmetic count-claim drift; not a substantive issue.

### User Sign-off

Phase 3 produces no UI changes — no sign-off needed.

## Phase — 2 Migrate Hardcoded Literals

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** ec6ec71

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | Pre-migration enumeration | Done | 23 source skill files identified across 6 categories; INJECTED-BLOCKQUOTE singled out at run-plan/SKILL.md:898-930 |
| 2.2 | Per-fence migration | Done | Helper-source preamble added per fence; 5 fixture literals + INJECTED-BLOCKQUOTE migrated; co_author hardcoded defaults dropped at commit/SKILL.md, quickfix/SKILL.md |
| 2.3 | Mirror sync | Done | `find skills -name '*.md'` diff loop empty (byte-identical) |
| 2.4 | Categorized re-audit | Done | Zero EXEC-FENCE drift remains; 17 hits remain (all PROHIBITION/MIGRATION-TOOL/PROSE-DESCRIPTIVE/fallback) |
| 2.5 | End-to-end fixture test | Done | tests/test-skill-file-drift.sh (12 cases) exercises migrated fence with timezone:Europe/London + testing.full_cmd:FIXTURE_FULL; resolved values flow through |

### Verification

- **Test suite:** PASSED (1237 baseline → 1249 after Phase 2, +12 fixture cases, 0 failures)
- **Audit grep classifications:** TZ 0/EXEC + 5/PROSE-DESCRIPTIVE; test:all 0/EXEC + 9/PROHIBITION-MIGRATION-TOOL-PROSE-DESCRIPTIVE; npm start 0/EXEC + 3/PROHIBITION-MIGRATION-TOOL; .test-results.txt all in `${TEST_OUTPUT_FILE:-.test-results.txt}` form or out-of-scope contexts
- **INJECTED-BLOCKQUOTE structural AC:** PASS (no raw `npm start`/`npm run test:all`/`.test-results.txt`; `$DEV_SERVER_CMD`/`$TEST_OUTPUT_FILE`/`$FULL_TEST_CMD` all present)
- **Mirror parity:** clean
- **Substitution discipline strengthening:** `skills/run-plan/SKILL.md:181` now enumerates all 3 vars (`$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, `$TEST_OUTPUT_FILE`)

### Test-harness collateral changes (verified contractually equivalent)

- `tests/test-skill-conformance.sh` "run-plan test capture redirect" — literal-match for `.test-results.txt"` updated to regex matching the migrated `${TEST_OUTPUT_FILE:-.test-results.txt}` pattern. Same intent (capture-not-pipe contract).
- `tests/test-quickfix.sh` case 10 — was asserting `$CO_AUTHOR` + `BASH_REMATCH` in skill body; now asserts `$COMMIT_CO_AUTHOR` + helper-source line. The CO_AUTHOR resolution logic moved to the helper by design; the assertion follows.
- `tests/test-quickfix.sh` extracted-script harness — added `: "${CLAUDE_PROJECT_DIR:=$(pwd)}"` so the helper's mandatory env var is satisfied inside the synthetic fixture (which `cd`s into `$FIX` before running the extracted script).

### Acceptance Criteria — all met

| AC | Verdict |
|----|---------|
| Zero EXEC-FENCE for `TZ=America/New_York` | PASS |
| Zero EXEC-FENCE for `npm run test:all` | PASS |
| Zero EXEC-FENCE for `npm start` | PASS |
| Mirror parity (skills ↔ .claude/skills) | PASS |
| Full test suite | PASS (1249/1249) |
| Synthetic-fixture test (London config flows through) | PASS |
| INJECTED-BLOCKQUOTE structural AC | PASS |

### Plan-Text Drift

- `bullet=Categories field=tz-count plan=60 actual=60` — matches once you separate EXEC vs PROSE-DESCRIPTIVE
- `bullet=Categories field=test-results-count plan=16 actual=13-in-scope` — plan undercount of in-scope migrations vs total raw-audit hits; informational
- `bullet=Categories field=npm-start-count plan=2-EXEC+1-PROSE actual=3-EXEC+1-PROSE+1-injected` — `manual-testing/SKILL.md:19` was a third EXEC-FENCE site not enumerated in plan; informational

### User Sign-off

Phase 2 produces no UI changes — no sign-off needed.

## Phase — 1 Canonical Config-Resolution Helper Script

**Plan:** plans/SKILL_FILE_DRIFT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-file-drift-fix
**Branch:** feat/skill-file-drift-fix
**Commit:** d2b05c3

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Author `zskills-resolve-config.sh` (source + mirror) | Done | 64 lines; resolves UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, DEV_SERVER_CMD, TEST_OUTPUT_FILE, COMMIT_CO_AUTHOR via BASH_REMATCH; CLAUDE_PROJECT_DIR fail-loud; idempotent; no jq; _ZSK_ internals unset; coexists w/ zskills-stub-lib.sh |
| 1.2 | commit.co_author schema + install (verification-only) | Done | Schema default at config/zskills-config.schema.json:52; backfill at skills/update-zskills/SKILL.md:220-235 — both pre-exist (refine-1 R1.7). Phase 1 added 5 backfill regression tests in test-update-zskills-rerender.sh. |
| 1.3 | Author `references/canonical-config-prelude.md` | Done | 216 lines; 7 sections (sourcing pattern, fallback semantics, mode files, subagent dispatch, shell-state scope, heredoc-form, allowlist marker) |

### Verification

- **Test suite:** PASSED (1213 baseline → 1237 after Phase 1, +24 new tests, 0 failures)
- **Hard rules:** zero `jq` invocations; all 6 vars empty-init-guarded; CLAUDE_PROJECT_DIR fail-loud; mirror byte-identical
- **Coexistence with `zskills-stub-lib.sh`:** confirmed (zero shared variable assignments; domain-disjoint)
- **PLAN-TEXT-DRIFT detected:** baseline test count was 1212 in plan; current main is 1213 (+1 = 0.08% drift; within Phase 3.5 auto-correct band). Implementer self-flagged.

### Acceptance Criteria — all 7 met

| AC | Test | Verdict |
|----|------|---------|
| Synthetic-fixture (London/FIXTURE_CMD/Test Author + 3 empties) | test-zskills-resolve-config.sh Test 1a-f | PASS |
| Idempotency | Test 2 | PASS |
| Empty-config | Test 3a-b | PASS |
| Malformed-config | Test 4a-b | PASS |
| CLAUDE_PROJECT_DIR-switching (London ↔ Tokyo) | Test 5a-b | PASS |
| Prelude doc + 7 sections | Test 6a-c | PASS |
| Install integrity (mirror-skill.sh + byte-identical) | Test 7a-c | PASS |

### Plan-Text Drift

- `bullet=AC8 field=baseline-test-count plan=1212 actual=1213` — Phase 3.5 auto-correct candidate (small drift; informational). Plan AC at line ~244 says "Refine-1 verified count is **1212**"; current main `59cbb2c` (post-PR-#119/#120/#121) is 1213. Worth updating in a follow-up but non-blocking.

### User Sign-off

Phase 1 produces no UI changes — no sign-off needed.

### Notes

Phase 0 (staleness gate) was run inline as orchestrator preflight; all 5 checks passed against main `59cbb2c`. No code changes for Phase 0; tracker mark only (commit `5b84112`).
