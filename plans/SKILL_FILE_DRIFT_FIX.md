---
title: Skill-File Drift Fix — Runtime Config Resolution in Skill Bash Fences
created: 2026-04-25
status: active
---

# Plan: Skill-File Drift Fix

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Close the architectural gap left by `plans/DRIFT_ARCH_FIX.md`. That plan migrated CODE consumers (hooks, helper scripts) to runtime config-read and TEXT consumers (CLAUDE.md → `.claude/rules/zskills/managed.md`) to render-time fill + drift-warn. It declared itself a fix for "a systemic drift-bug class" but never mentioned a third category: **skill `.md` files containing executable bash fences** that the orchestrator (or dispatched subagents) execute literally.

A hardcode audit (verified independently by re-grep across 3 review rounds, then re-derived against current main `e3acd40` in /refine-plan refine-1) found drift across **6 config-field categories** (the original audit swept 3; refine round 3 caught 3 more — `.test-results.txt`, `scripts/port.sh`, `co_author` — that the original sweep missed; refine-1 dropped `scripts/port.sh` from scope after verifying it had landed via SCRIPTS_INTO_SKILLS_PLAN PRs #94-#100):

- **60 sites**: `TZ=America/New_York` inside bash fences as `$(TZ=America/New_York date ...)` subshells (EXEC-FENCE form). Config: `timezone`. Per-file: 10 run-plan/SKILL.md, 9 fix-issues/SKILL.md, 6 run-plan/modes/pr.md, 5 work-on-plans/SKILL.md, 5 verify-changes/SKILL.md, 5 draft-plan/SKILL.md, 4 refine-plan/SKILL.md, 4 fix-issues/modes/direct.md, 3 fix-issues/modes/pr.md, 2 fix-issues/modes/cherry-pick.md, 2 do/modes/pr.md, 1 each in zskills-dashboard/SKILL.md, run-plan/modes/cherry-pick.md, quickfix/SKILL.md, fix-issues/references/failure-protocol.md, commit/modes/land.md.
- **8 sites**: `npm run test:all` inside bash fences (EXEC-FENCE form). Config: `testing.full_cmd`. Sites: `skills/commit/modes/land.md:41`, `skills/fix-issues/modes/cherry-pick.md:33,97`, `skills/fix-issues/modes/direct.md:157`, `skills/investigate/SKILL.md:208`, `skills/qe-audit/SKILL.md:261`, `skills/run-plan/modes/cherry-pick.md:96,135`.
- **2 sites**: `npm start` inside bash fences (EXEC-FENCE form). Config: `dev_server.cmd`. Sites: `skills/manual-testing/SKILL.md:19`, `skills/verify-changes/SKILL.md:404`.
- **8 sites**: `npm run test:all` in PROSE-IMPERATIVE form (each line read by re-grep + manual classification). Implementing agent re-derives at execution time via `grep -nE 'npm run test:all' skills/` filtered to bullet/numbered-list/imperative-verb form. Currently (refine-1): `skills/commit/SKILL.md:250`, `skills/do/modes/direct.md:18`, `skills/do/SKILL.md:342`, `skills/doc/SKILL.md:282,314`, `skills/fix-issues/SKILL.md:777,1130`, `skills/qe-audit/SKILL.md:283`. The model executes them as instructions even though they're not in fences. Same drift class. Brought into scope refine round 3.
- **16 sites**: `$TEST_OUT/.test-results.txt` hardcoded filename suffix — 7 EXEC-FENCE writes (`investigate:208`, `quickfix:546`, `run-plan:1205`, `run-plan:909` [INJECTED-BLOCKQUOTE], `run-plan:925` [INJECTED-BLOCKQUOTE], `verify-changes:307`, `verify-changes:349`); 7 EXEC-FENCE reads (`investigate:210` [refine-2 DA2.11 added — was missed in refine-1], `quickfix:547`, `run-plan:1240`, `run-plan:916` [INJECTED-BLOCKQUOTE], `verify-changes:310`, `verify-changes:314`, `verify-changes:334`); 2 mode-file comments (`run-plan/modes/pr.md:491,495`). Total 7+7+2=16. The INJECTED-BLOCKQUOTE sites at `:909,:916,:925` are migrated via the model-side substitution discipline (see Phase 2 WI 2.2 INJECTED-BLOCKQUOTE sub-bullet). Two additional **non-anchored** prose-descriptive hits (`run-plan/SKILL.md:820` and `update-zskills/SKILL.md:276`) contain the substring `.test-results.txt` but NOT `$TEST_OUT/.test-results.txt` — out of scope (descriptive prose / schema-default content), tracked separately under PROSE-DESCRIPTIVE in the Phase 2 enumeration. Config: `testing.output_file`. Brought into scope refine round 3.
- **2 sites + schema**: `CO_AUTHOR="Claude Opus 4.7 (1M context) <noreply@anthropic.com>"` hardcoded default-then-config-override pattern at `skills/commit/SKILL.md:291` and `skills/quickfix/SKILL.md:603` (3 additional `CO_AUTHOR=` BASH_REMATCH assignments at `commit/SKILL.md:295`, `quickfix/SKILL.md:605`, `update-zskills/SKILL.md:222` are extraction logic, not the hardcoded-default pattern, and stay). Skills drop the hardcoded default entirely; helper resolves `COMMIT_CO_AUTHOR` from config; the version-specific identity is **already** carried by `config/zskills-config.schema.json`'s default for `commit.co_author` (verified present at line 55) and `/update-zskills` Step 3.5 **already** backfills the field on rerender (verified at `skills/update-zskills/SKILL.md:226-234`). Skills emit the Co-Authored-By trailer conditionally (skip if empty — supports consumer opt-out via blank config value). Single source of truth for the version string is the schema; updates flow via schema bumps + /update-zskills --rerender.
- **PROSE-IMPERATIVE npm start (1 site)** at `skills/verify-changes/SKILL.md:687` (refine-2 DA2.10 — was missed in earlier enumeration; bullet + sentence-start `Run` + code-span `\`npm start &\``). Migrates to `$DEV_SERVER_CMD` per Phase 2 WI 2.2 PROSE-IMPERATIVE migration sub-bullet, with substitution-discipline coverage per refine-2 R2.12 fix.
- **VERBATIM-INJECTED blockquote (1 multi-literal site)** at `skills/run-plan/SKILL.md:898-930`. Declared "Include this VERBATIM in every implementation and verification agent prompt" and contains literal `npm start &` (line 903), `$TEST_OUT/.test-results.txt` (lines 909, 916, 925), and `$FULL_TEST_CMD` references (909, 919, 925). Migration uses model-side `$VAR` substitution discipline (matching the existing convention at `skills/run-plan/SKILL.md:181`) — see Phase 2 WI 2.2 INJECTED-BLOCKQUOTE sub-bullet. Refine-1 introduced a `__SNAKE__`-marker + `sed` pre-emission mechanism; refine-2 (R2.1/R2.2/R2.8/DA2.1/DA2.2/DA2.3) verified that mechanism had no host fence (the `RAW_RECIPE_TEXT` source variable does not exist anywhere in the codebase) AND broke on `|` characters in config values, and replaced it with the simpler `$VAR`-discipline approach. Phase 4 enforcement (deny-list + structural AC) catches regressions on the migrated form.

**Total: ~97 hardcoded references across 27 skill files** (60 TZ EXEC + 8 test-cmd EXEC + 2 dev-server EXEC + 8 PROSE-IMPERATIVE test-cmd + 16 testing.output_file + 2 co_author hardcoded-default + 1 PROSE-IMPERATIVE npm start = 97; refine-2 R2.4 reconciled the earlier 96-vs-97 inconsistency by using 97 consistently). The INJECTED-BLOCKQUOTE site at `skills/run-plan/SKILL.md:898-930` contains multiple literals already counted in the testing.output_file (3 `$TEST_OUT/.test-results.txt` instances at :909/:916/:925) and dev-server (1 `npm start &` instance at :903) categories above — not double-counted. Counts re-derived /refine-plan refine-1 against main `e3acd40`, re-confirmed in refine-2 against the same anchor; replaces stale "85 across 26 skill files" arithmetic. The implementing agent re-derives at execution time — line numbers will continue to drift in highly-edited files (commit/SKILL.md, fix-issues/SKILL.md, run-plan/SKILL.md).

**Verified clean** (audit re-run confirms zero hardcoded hits in skill bash fences):
- `dev_server.main_repo_path` (`/workspaces/`) — 0 hits
- `ui.auth_bypass` — 0 user-facing hits (only update-zskills' own MIGRATION-TOOL references)
- `agents.min_model` (literal `"opus"|"sonnet"|"haiku"` in agent dispatches) — 0 hits

**Verified DESCRIPTIVE** (out of scope, no model execution): `skills/do/SKILL.md:350` (lists verify-changes activities), `skills/do/SKILL.md:404` (example output), `skills/fix-issues/references/failure-protocol.md:95` (failure trigger condition), `skills/fix-report/SKILL.md:407` (template content), `skills/run-plan/references/failure-protocol.md:90` (failure trigger condition).

**Verified PROHIBITION** (allowlist marker required): `skills/do/SKILL.md:335` ("do NOT run `npm test` or `npm run test:all`" — explicit prohibition).

**zskills meta-context (load-bearing).** zskills is a project USING zskills — its own `.claude/zskills-config.json` happens to set `testing.full_cmd: "bash tests/run-all.sh"` and `timezone: "America/New_York"`, so its own skill files appear functional even with hardcodes. But these skill files are SHIPPED to downstream projects via `/update-zskills`. A hardcoded `TZ=America/New_York` becomes a literal hardcode in every downstream that copies the skill — silently overriding their configured timezone. The drift surface is therefore N projects wide, not just zskills itself.

**Architectural pattern (corrected from round 1 review).** The Bash tool's docstring states: "shell state does not [persist between calls]." Each Bash tool invocation is a fresh subshell. Therefore, `$FULL_TEST_CMD` set in a skill's preflight bash fence is **NOT visible to subsequent fences in the same skill** — let alone fences in mode files or dispatched subagents. The existing pattern in `skills/run-plan/modes/pr.md:325-345` confirms this: the file **re-reads config inline at point of use**, with the comment *"Do NOT rely on $CONFIG_CONTENT from earlier -- context compaction may have lost it."* The plan adopts this pattern uniformly: the canonical config-read block is inlined wherever config-derived values are used, not centralized in a preflight that subsequent fences inherit from.

The plan resolves four architectural gaps:
1. No canonical pattern for skill files to resolve config-derived values beyond `$FULL_TEST_CMD`. Each consumer reinvents.
2. `.claude/hooks/block-unsafe-project.sh:311` has `${FULL_TEST_CMD:-npm run test:all}` — npm-specific fallback that contradicts zskills's framework-agnostic stance. Verified present in the codebase (commit f00e7c1).
3. Test-infra detection logic is duplicated between `block-unsafe-project.sh` and `verify-changes/SKILL.md` with no sync mechanism — divergence risk.
4. No enforcement mechanism prevents new hardcodes. The prohibition at `skills/run-plan/SKILL.md:179` is prose-only and visibly failed (6 hardcodes accumulated despite the rule).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 0 — Staleness gate (halt if SCRIPTS_INTO_SKILLS_PLAN not landed) | ✅ Done | gate-only (no commit) | All 5 checks pass on main 59cbb2c (frontmatter + 4 anchor pairs + CLAUDE_PROJECT_DIR export + CHANGELOG entry). Inline preflight; no implementation needed. |
| 1 — Canonical config-resolution helper resolves 6 vars (UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, DEV_SERVER_CMD, TEST_OUTPUT_FILE, COMMIT_CO_AUTHOR) | ✅ Done | (squash) | helper script + .claude mirror + canonical-config-prelude reference doc + 24 new tests; coexists with zskills-stub-lib.sh; 1237/1237 |
| 2 — Migrate ~97 hardcoded references across 6 categories (60 TZ + 8 test-cmd EXEC + 2 dev-server + 8 PROSE-IMPERATIVE test-cmd + 1 PROSE-IMPERATIVE npm start + 16 output_file + 2 co_author); resolve verbatim-injected blockquote | ✅ Done | (squash) | 50 files (23 source + 23 mirror + 4 tests); helper-source preamble added per fence; INJECTED-BLOCKQUOTE migrated via model-side `$VAR` discipline; 1237 → 1249 (+12 fixture cases) |
| 3 — Fix opinionated fallbacks in hooks (block-unsafe-project.sh:311 + sweep for others); sync test-infra detection list | ✅ Done | (squash) | three-case tree at pipe gate; 26-fallback sweep (1 opinionated fixed, 25 sensible kept); shared fixture `tests/fixtures/test-infra-patterns.txt` (9 patterns) + sync test; testing.output_file-aware suggestion message; 1249 → 1258 |
| 4 — Enforcement: test deny-list (4-entry fixture) + drift-warn hook extension + prose-imperative detection + allowlist comment convention | ✅ Done | (squash) | 10 files (5 source + 5 mirrors); 4-entry fixture; all-fence tracker (refines spec pseudocode); 2 surfaced drift sites markered (do/SKILL.md:401 npm-test report-template, update-zskills/SKILL.md:613 npm-start render-report); allowlist convention in CLAUDE_TEMPLATE.md; 1258 → 1268 (+10) |
| 5 — Verification + drift-regression test | 🟡 In Progress | | |

## Phase 0 — Staleness Gate

### Goal

Halt `/run-plan` cleanly if `plans/SCRIPTS_INTO_SKILLS_PLAN.md` has not landed. This plan places the new helper at `skills/update-zskills/scripts/zskills-resolve-config.sh` per SCRIPTS_INTO_SKILLS_PLAN's "Tier 1 = skill machinery in owning skill" framework. Before that plan lands, `skills/<owner>/scripts/` is not yet the canonical home for skill-machinery scripts and ~16 scripts still live at top-level `scripts/`. Landing this plan first would either (a) place the new helper at top-level `scripts/` (re-introducing the pollution that SCRIPTS_INTO_SKILLS_PLAN is fixing), or (b) pioneer a non-existent layout pattern — both wrong.

### Work Items

- [ ] 0.1 — **Frontmatter check.** Use whitespace-tolerant regex (refine-1 R1.18) so a normalized `status:complete` or `status:  complete` doesn't slip through.

  ```bash
  FAIL=
  grep -qE '^status:[[:space:]]*complete' plans/SCRIPTS_INTO_SKILLS_PLAN.md \
    || { echo "FAIL: prerequisite plan frontmatter not 'status: complete'" >&2; FAIL=1; }
  ```

  **Note (refine-1 R1.1, R1.19):** As of refine-1 verification against main `e3acd40`, all four anchor pairs already PASS, the test-runner export already exists, the CHANGELOG entry is present, and `plans/SCRIPTS_INTO_SKILLS_PLAN.md` frontmatter is `status: complete`. The gate is therefore decorative on current main but stays in place as a safety net for re-runs against historical states. **Phase 0 deliberately does NOT gate on `ZSKILLS_MONITOR_PLAN` or `CONSUMER_STUB_CALLOUTS_PLAN`** — those plans are independent. ZSKILLS_MONITOR added two new skills (`/work-on-plans`, `/zskills-dashboard`) which contributed 6 new EXEC TZ migration sites (handled in Phase 2 WI 2.2 enumeration); CONSUMER_STUB_CALLOUTS added a domain-disjoint helper (`zskills-stub-lib.sh`) at the same `skills/update-zskills/scripts/` directory, no conflict (see Phase 1 D&C).

- [ ] 0.2 — **Filesystem anchor check.** Verify the post-refactor state via four symmetric anchor pairs (legacy absent + new present), spanning multiple owning skills so partial-completion states fail at least one anchor. Each gets a distinct FAIL message:

  ```bash
  test ! -e scripts/port.sh \
    || { echo "FAIL: legacy scripts/port.sh still present" >&2; FAIL=1; }
  test -f skills/update-zskills/scripts/port.sh \
    || { echo "FAIL: skills/update-zskills/scripts/port.sh missing" >&2; FAIL=1; }
  test ! -e scripts/sanitize-pipeline-id.sh \
    || { echo "FAIL: legacy scripts/sanitize-pipeline-id.sh still present" >&2; FAIL=1; }
  test -f skills/create-worktree/scripts/sanitize-pipeline-id.sh \
    || { echo "FAIL: skills/create-worktree/scripts/sanitize-pipeline-id.sh missing" >&2; FAIL=1; }
  test ! -e scripts/clear-tracking.sh \
    || { echo "FAIL: legacy scripts/clear-tracking.sh still present" >&2; FAIL=1; }
  test -f skills/update-zskills/scripts/clear-tracking.sh \
    || { echo "FAIL: skills/update-zskills/scripts/clear-tracking.sh missing" >&2; FAIL=1; }
  test ! -e scripts/write-landed.sh \
    || { echo "FAIL: legacy scripts/write-landed.sh still present" >&2; FAIL=1; }
  test -f skills/commit/scripts/write-landed.sh \
    || { echo "FAIL: skills/commit/scripts/write-landed.sh missing" >&2; FAIL=1; }
  ```

- [ ] 0.3 — **Test-runner export check (load-bearing).** Phase 1's helper resolves config via `$CLAUDE_PROJECT_DIR`; tests source the helper through fixtures that depend on `tests/run-all.sh` exporting this var (SCRIPTS_INTO_SKILLS_PLAN Phase 5 WI 5.7). Without the export, fixtures resolve under empty `$CLAUDE_PROJECT_DIR` and silently fail.

  ```bash
  grep -qF 'export CLAUDE_PROJECT_DIR' tests/run-all.sh \
    || { echo "FAIL: tests/run-all.sh missing CLAUDE_PROJECT_DIR export (SCRIPTS_INTO_SKILLS_PLAN Phase 5 WI 5.7 prerequisite)" >&2; FAIL=1; }
  ```

- [ ] 0.4 — **CHANGELOG entry check.** Tolerant regex captures the spirit (Tier-1 → owning skills) without breaking on minor copy-edits:

  ```bash
  grep -E 'Tier.?1.*owning skills?|move.*scripts.*into.*skills|relocate.*scripts.*under.*skills' CHANGELOG.md \
    || { echo "FAIL: CHANGELOG entry for Tier-1 scripts → owning skills not found" >&2; FAIL=1; }
  ```

- [ ] 0.5 — **Halt with actionable message on any failure.**

  ```bash
  if [ -n "$FAIL" ]; then
    cat >&2 <<'EOF'
  HALT: This plan depends on plans/SCRIPTS_INTO_SKILLS_PLAN.md landing first.

  Prerequisite check failed (see FAIL lines above).

  Fix:
    1. /run-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md
    2. Wait for it to land (status: complete in frontmatter,
       Tier-1 scripts moved into owning skills' scripts/ subdirs).
    3. /run-plan plans/SKILL_FILE_DRIFT_FIX.md
    (Optional, if more than ~1 week elapsed between the prereq
    landing and this re-run: /refine-plan first to catch any
    line-number drift in this plan's :NNN citations.)
  EOF
    exit 1
  fi
  ```

  The implementing agent **MUST NOT** attempt to land the prerequisite itself; the user owns ordering.

### Acceptance Criteria

- [ ] All checks pass; `/run-plan` proceeds to Phase 1.
- [ ] If any check fails, plan execution halts cleanly with the actionable message; the plan's `status: active` frontmatter is preserved so a re-run after the prerequisite lands re-hits the gate and proceeds.

### Dependencies

None — Phase 0 IS the dependency check.

## Phase 1 — Canonical Config-Resolution Helper Script

### Goal

Add `skills/update-zskills/scripts/zskills-resolve-config.sh` (mirrored to `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`) — a sourceable helper that resolves config-derived values (`UNIT_TEST_CMD`, `FULL_TEST_CMD`, `TIMEZONE`, `DEV_SERVER_CMD`) into shell vars at the point of source. Skill bash fences source the helper at the top — one line — and reference `$VAR` for the rest of the fence. Single source of truth for the resolution logic; no per-fence boilerplate to drift. Owner is `update-zskills` since config-resolution is its domain (per SCRIPTS_INTO_SKILLS_PLAN's classification rule).

### Work Items

- [ ] 1.1 — Author **`skills/update-zskills/scripts/zskills-resolve-config.sh`** (source) AND **`.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`** (mirror — drift-check enforces byte parity, same as SKILL.md mirroring). The script:
  - Resolves **6 vars** from `.claude/zskills-config.json` via bash regex (no jq): `UNIT_TEST_CMD`, `FULL_TEST_CMD`, `TIMEZONE`, `DEV_SERVER_CMD`, `TEST_OUTPUT_FILE`, `COMMIT_CO_AUTHOR`. Add the new var reads:

    ```bash
    if [[ "$_ZSK_CFG_BODY" =~ \"output_file\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      TEST_OUTPUT_FILE="${BASH_REMATCH[1]}"
    fi
    if [[ "$_ZSK_CFG_BODY" =~ \"commit\"[[:space:]]*:[[:space:]]*\{[^}]*\"co_author\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      COMMIT_CO_AUTHOR="${BASH_REMATCH[1]}"
    fi
    ```

    All 6 vars initialized to empty string before the regex test (consumer-decides empty handling per Phase 1.2).
  - Locates the config relative to `$CLAUDE_PROJECT_DIR` (the harness-set project root; matches SCRIPTS_INTO_SKILLS_PLAN convention at lines 175-195 — bare-relative paths are forbidden, `$REPO_ROOT/...` is for source-tree tests, `$CLAUDE_PROJECT_DIR/...` is for shipped/cross-skill code). The harness sets `CLAUDE_PROJECT_DIR` in spawned bash blocks; `tests/run-all.sh` exports `CLAUDE_PROJECT_DIR="$REPO_ROOT"` per SCRIPTS_INTO_SKILLS_PLAN Phase 5 WI 5.7. The helper internally uses `${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR not set — harness or tests/run-all.sh export missing}` to fail loud if the env var is absent rather than silently expanding to an empty path. Worktree-correctness: each worktree's checkout has its own `.claude/zskills-config.json` since the file is git-tracked; `CLAUDE_PROJECT_DIR` resolves per-worktree because the harness sets it from the running session's CWD/repo-root.
  - Initializes each var to empty string BEFORE the regex test (empty-pattern-guard lesson from DRIFT_ARCH_FIX Phase 1).
  - `unset`s `_ZSK_`-prefixed internals at end so the caller's environment is clean except for the four exported vars.
  - Is idempotent — sourcing twice yields the same vars.
  - Has NO opinionated defaults. Empty config = empty vars; consumer decides what to do.
  - Handles malformed JSON gracefully — if the regex fails to match (broken JSON, missing field, unusual whitespace), the var stays empty rather than aborting. Resolves Round-3 finding 3.2.

- [ ] 1.2 — **Verify schema + backfill present for `commit.co_author`** (refine-1 R1.7 — already-done reframe). The schema declaration AND the backfill logic both already exist on current main. WI 1.2 is verification-only:
  - Confirm `config/zskills-config.schema.json` (NOT `.claude/zskills-config.schema.json` — that path is the consumer-installed copy generated by `/update-zskills`; source-of-truth is `config/`) declares `commit.co_author` with default `"Claude Opus 4.7 (1M context) <noreply@anthropic.com>"`. Verified at line 55 as of refine-1.
  - Confirm `/update-zskills` Step 3.5 backfills the field. Verified at `skills/update-zskills/SKILL.md:226-234` as of refine-1.
  - **If backfill regression test for `commit.co_author` doesn't already exist** in `tests/test-update-zskills-rerender.sh` (or equivalent), add one asserting backfill behavior. Run `grep -nE 'co_author' tests/` to determine.
  - Align with the new helper-resolution path: the helper in WI 1.1 reads `commit.co_author` via bash regex; the schema's default value flows into `.claude/zskills-config.json` via /update-zskills install/rerender; the helper resolves it as `$COMMIT_CO_AUTHOR`. No new schema or backfill work — Phase 2's skills drop their hardcoded `CO_AUTHOR=` defaults and source from helper.

- [ ] 1.3 — Author **`references/canonical-config-prelude.md`** in zskills repo root (reference doc; not installed downstream). Documents:
  - **Sourcing pattern** for skill fences (verbatim, copy-pasteable):

    ```bash
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    # vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR
    ```

    **One-line preamble per fence** (refine-2 DA2.4: corrected from earlier `--show-toplevel` references which contradicted refine-1's convention shift). Uses `$CLAUDE_PROJECT_DIR` so the helper resolves config from the current worktree's checkout (the harness sets `CLAUDE_PROJECT_DIR` per-worktree from the running session's CWD/repo-root; each worktree has its own `.claude/zskills-config.json` since the file is git-tracked). Resolves Round-3 finding 3.6. Helper script's internal config resolution also uses `$CLAUDE_PROJECT_DIR` (NOT `git rev-parse --show-toplevel`) so the caller doesn't need to pre-resolve any paths and the convention matches SCRIPTS_INTO_SKILLS_PLAN lines 175-195.

  - **Fallback semantics**. General principle: empty value = "not configured for this project"; the helper produces empty values, never opinionated defaults. Specific application at consumer sites:
    - **Critical-path consumers** (test-gates, deploy-gates): `if [ -z "$FULL_TEST_CMD" ]; then echo "ERROR: testing.full_cmd not configured. Run /update-zskills." >&2; exit 1; fi`. Worked example shown.
    - **Informational consumers** (timestamp formatters): `TZ="${TIMEZONE:-UTC}"`. Worked example shown. Resolves DA1.5.

  - **Mode files** also source the helper at the top of any fence that needs config. Do NOT inherit from a parent skill's preflight — context compaction may have lost orchestrator state (verified empirically; see `skills/run-plan/modes/pr.md:325-345` comment).

  - **Subagent dispatch prompts** include resolved literals, not `$VAR` references. The orchestrator sources the helper once before dispatch and substitutes the literal value into the prompt text. Matches `skills/run-plan/SKILL.md:181`.

  - **Within ONE bash fence** (one Bash tool invocation), shell state persists — sourcing once at the top of a fence makes `$VAR` available throughout that fence. Across fences, no.

  - **Heredoc-form interaction**. With the helper sourced inside the SAME fence as the heredoc-using code, `$VAR` is in scope for unquoted `<<TAG` heredoc bodies (which expand vars). Quoted `<<'TAG'` heredocs do NOT expand — the migration handles this by capturing the resolved value into a literal before the heredoc opener. Spot-check found 3 quoted heredocs in `commit/SKILL.md` and `review-feedback/SKILL.md`, but none in the TZ-bound migration set. Phase 2.1 enumerates conclusively before migration.

  - **Allowlist marker format spec** (used by Phase 4):

    ```
    <!-- allow-hardcoded: <literal> reason: <one-line explanation> -->
    ```

    Lowercase `allow-hardcoded:`. `<literal>` is the forbidden string verbatim, **delimited by ` reason:`** (i.e., capture is "everything between `allow-hardcoded: ` and ` reason:`, trimmed"). This supports multi-token literals like `npm run test:all` and `npm start` (refine-round-2 finding 2.2). `<reason>` excludes the substring `-->` and `reason:` (rephrase if needed). **Marker scope**: the marker lives in MARKDOWN PROSE on the line IMMEDIATELY ABOVE a fence-opener (` ```bash ` / ` ```sh ` / ` ```shell `). Such a marker exempts hits of EXACTLY `<literal>` (verbatim string match, not regex) inside the immediately-following fence. For a fence with multiple distinct allowed literals, place multiple markers on consecutive lines above the fence (one per literal); the test reads upward from the fence-opener until a non-marker line. Markers inside fences (as bash comments) are NOT supported. Markers further than the contiguous-marker-block above the fence-opener are NOT supported. Test grep pattern documented (canonical regex used by Phase 4.1).

### Design & Constraints

**Helper-script mechanism (Option B from research, re-evaluated post-round-2).** Round 2 surfaced a real blocker against the inline-per-fence design: 30-40 fences each with ~25 lines of inlined boilerplate (~1000 lines duplicated) WILL drift over time, and reviewers will skip the boilerplate (DA2.1, DA2.2). The original Option B rejection cited "install dependency" — but `scripts/` already ships 10+ helper scripts via `/update-zskills` (`port.sh`, `apply-preset.sh`, `sanitize-pipeline-id.sh`, etc.), so adding one more is consistent infrastructure, not a new dependency. Single source of truth eliminates the divergence risk.

**One-line preamble per fence** (post round-3 simplification + post-Phase-0 path correction): `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`. Affected fences: **~67** (refine-1 R1.11 — re-derived by awk fence-state pass over the 27 files containing drift hits; the original "~40" estimate predated refine-3's scope expansion). Total new lines: ~67 (preamble) + ~96 (per-literal substitution; one per drift-hit) + ~32 (critical-path empty-checks) ≈ **~195 lines added** across the migration, vs ~1000 with inline blocks. Reviewer-fatigue mitigation argument still holds (~200 << ~1000); just with a corrected number.

**Helper coexistence with `zskills-stub-lib.sh`** (refine-1 R1.9). The same directory `skills/update-zskills/scripts/` already hosts `zskills-stub-lib.sh` (CONSUMER_STUB_CALLOUTS_PLAN landing). The two are **domain-disjoint**: stub-lib exposes `zskills_dispatch_stub <name> <repo-root>` for invoking consumer-customizable stubs (`scripts/<name>` callouts like `dev-port.sh`); the new `zskills-resolve-config.sh` resolves zskills-config fields into shell vars. Verified by reading both: no shared callers, no shared contracts, no overlapping code paths. **No merge needed.** They coexist as two helpers in the same skill machinery directory — the directory is the unifying concept (Tier-1 owning-skill convention from SCRIPTS_INTO_SKILLS_PLAN), not the helpers themselves.

**Forward-looking shared-infrastructure note** (refine-2 R2.11). No shared infrastructure factored at this stage — both helpers internally resolve `$CLAUDE_PROJECT_DIR` and `$REPO_ROOT` via the convention from SCRIPTS_INTO_SKILLS_PLAN lines 175-195 (already a documented standard, not duplicated logic). If a third helper joins this directory (e.g., a future `zskills-validate-config.sh` for config schema validation), evaluate at that point whether `$CLAUDE_PROJECT_DIR`/`$MAIN_ROOT` resolution and the BASH_REMATCH config-parser idiom warrant extraction to a `_zskills-paths.sh` shared lib. Today's two-helper directory is below the "rule of three" threshold for premature factoring.

**Reuse the verbatim runtime-read idiom from DRIFT_ARCH_FIX** (lines 86-115 of that plan). The helper's body IS that block, with two added field reads:

```bash
if [[ "$_ZSK_CFG_BODY" =~ \"timezone\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  TIMEZONE="${BASH_REMATCH[1]}"
fi
if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
  DEV_SERVER_CMD="${BASH_REMATCH[1]}"
fi
```

**Install integrity.** The helper script is shipped to downstream as part of the `update-zskills` skill mirror at `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` (per SCRIPTS_INTO_SKILLS_PLAN's "skill machinery installs via skill mirror, not via Step D scripts copy"). Phase 1 includes a verification step: run `/update-zskills` against a clean fixture and assert `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` is present in the rendered output.

**Allowlist marker format** (referenced by Phase 4). Documented in `references/canonical-config-prelude.md`:

```
<!-- allow-hardcoded: <literal> reason: <one-line explanation> -->
```

- Marker is case-sensitive (lowercase `allow-hardcoded:`).
- `<literal>` is the forbidden string verbatim — no escaping.
- `<reason>` may contain any characters except the substring `-->`. Reasons containing `-->` MUST rewrite to avoid it (e.g. `--&gt;` or rephrase).
- Marker scope: same line as the literal, OR the line immediately preceding. Markers further away are not honored.
- Test-deny-list grep pattern (canonical, used by Phase 4): the test reads each skill `.md` file, finds lines containing a forbidden literal, then checks whether the same line or the line immediately above contains a `<!-- allow-hardcoded: <literal> reason: ... -->` marker that names the same literal verbatim.

### Acceptance Criteria

- [ ] `skills/update-zskills/scripts/zskills-resolve-config.sh` (and its `.claude/` mirror) exists, resolves all 6 vars correctly, and passes a synthetic-fixture test: temp dir with `.claude/zskills-config.json` containing `timezone: "Europe/London"`, `testing.full_cmd: "FIXTURE_CMD"`, `commit.co_author: "Test Author <test@example.com>"`; source the script with `cd $temp_dir`; assert `$TIMEZONE == "Europe/London"`, `$FULL_TEST_CMD == "FIXTURE_CMD"`, `$COMMIT_CO_AUTHOR == "Test Author <test@example.com>"`, and `$UNIT_TEST_CMD`, `$DEV_SERVER_CMD`, `$TEST_OUTPUT_FILE` are empty (not set in fixture). Resolves DA1.10 / R2 fixture concerns.
- [ ] Idempotency test: source the script twice; assert vars unchanged on second source.
- [ ] Empty-config test: temp dir without `.claude/zskills-config.json`; source; assert all 6 vars are empty strings (NOT unset, NOT opinionated default).
- [ ] Malformed-config test: temp dir with broken JSON in `.claude/zskills-config.json` (e.g. `{ "testing": broken }`); source; assert no exit/abort, vars remain empty strings. Resolves Round-3 finding 3.2.
- [ ] **CLAUDE_PROJECT_DIR-switching test** (refine-2 DA2.19 — simpler equivalent of the earlier git-worktree fixture test). The helper resolves config from `$CLAUDE_PROJECT_DIR`, so worktree-correctness reduces to a CLAUDE_PROJECT_DIR-switching test (no git-worktree fixture setup needed). Create two temp dirs `tmp1` and `tmp2` each with their own `.claude/zskills-config.json` (different `timezone` values: `tmp1` has `"Europe/London"`, `tmp2` has `"Asia/Tokyo"`); set `CLAUDE_PROJECT_DIR=$tmp1` and source helper → assert `$TIMEZONE == "Europe/London"`; set `CLAUDE_PROJECT_DIR=$tmp2` and source helper again (in a fresh subshell to avoid var-cache from idempotency) → assert `$TIMEZONE == "Asia/Tokyo"`. This verifies the harness-passive contract (the helper consumes `$CLAUDE_PROJECT_DIR` faithfully) without dragging in git-worktree mechanics. Resolves Round-3 finding 3.6 verification AND refine-2 DA2.19 simpler-equivalent fix.
- [ ] `references/canonical-config-prelude.md` exists and contains all 7 sections listed in WI 1.3.
- [ ] `update-zskills` install integrity test: run `/update-zskills` against a clean fixture; assert `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` is present in the rendered output. Resolves DA2.10 (downstream install behavior).
- [ ] All baseline tests still pass. Refine-1 verified count is **1212** (`bash tests/run-all.sh` against main `e3acd40` → `Overall: 1212/1212 passed, 0 failed`); the implementing agent re-derives at execution time and documents the count in the phase report rather than hardcoding here.

### Dependencies

Phase 0 (staleness gate). Otherwise self-contained.

## Phase 2 — Migrate Hardcoded Literals

### Goal

Replace ~96 hardcoded references across **6 categories** in skill `.md` files with `$VAR` references or — for the verbatim-injected blockquote — orchestrator-resolved literal substitution; ensure each affected fence sources the canonical helper at its top.

### Work Items

- [ ] 2.1 — **Pre-migration enumeration (re-derive at execution time; line numbers will drift).** Run `grep -rnB2 -E 'TZ=America/New_York|npm run test:all|npm start|\.test-results\.txt' skills/` and produce a hit-by-fence table: each row is one fence (file + opening-fence line) plus the literals it contains, the category (EXEC-FENCE, PROSE-IMPERATIVE, PROSE-DESCRIPTIVE, PROHIBITION, MIGRATION-TOOL, INJECTED-BLOCKQUOTE), and the heredoc form (unquoted `<<TAG`, quoted `<<'TAG'`, or non-heredoc). Also enumerate the verbatim-injected blockquote at `skills/run-plan/SKILL.md:898-930` separately (see WI 2.2 INJECTED-BLOCKQUOTE sub-bullet). Write to Phase 2 report. Spot-check found zero quoted heredocs in the TZ-migration set; WI 2.2 below treats this as the expected case and flags any contrary find.

  **Note on `scripts/port.sh`:** This category was in scope through refine round 3, but refine-1 (against main `e3acd40`) verified all 5 originally-cited sites had ALREADY migrated to `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/port.sh"` via SCRIPTS_INTO_SKILLS_PLAN PRs #94-#100. `grep -rE 'bash scripts/port\.sh|\(scripts/port\.sh\)' skills/` returns 0 hits. The category is **closed before this plan's execution begins**; scope reduced from 7 to 6 categories. See Drift Log.

- [ ] 2.2 — **Migration per fence.** For each fence in 2.1's table:
  - Add the **one-line preamble** at fence-top:

    ```bash
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    ```

    If the fence's heredoc-using code needs `$VAR` resolved before the heredoc opener (almost always — heredoc bodies expand vars at orchestrator bash time for unquoted `<<TAG`), the preamble at fence-top is the right placement. Worktree-aware via `$CLAUDE_PROJECT_DIR` (refine-2 DA2.4: corrected from earlier `--show-toplevel` references; the convention is `$CLAUDE_PROJECT_DIR` per refine-1's SCRIPTS_INTO_SKILLS_PLAN-alignment fix).

  - **Per-literal substitution within the fence**:
    - `TZ=America/New_York` → `TZ="${TIMEZONE:-UTC}"` (informational consumer; UTC fallback when config is empty).
    - `npm run test:all` → `$FULL_TEST_CMD` (critical-path consumer; preceded by fail-closed empty-check):

      ```bash
      if [ -z "$FULL_TEST_CMD" ]; then
        echo "ERROR: testing.full_cmd not configured. Run /update-zskills." >&2
        exit 1
      fi
      ```

    - `npm start &` → `$DEV_SERVER_CMD &` (critical-path; same fail-closed pattern with appropriate error message).
    - `$TEST_OUT/.test-results.txt` → `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}` (informational consumer; the filename suffix isn't load-bearing for project semantics, only for hook-output-detection — fall back is safe). **Exception: do NOT apply this substitution inside the verbatim-injected blockquote at `skills/run-plan/SKILL.md:898-930`** — see INJECTED-BLOCKQUOTE sub-bullet below.

  - **PROSE-IMPERATIVE migration — 8 `npm run test:all` sites + 1 `npm start` site at refine-1 grep time, re-derive before edit; refine-2 DA2.10 added verify-changes:687**:
    - Line numbers as of refine-1 verification (will drift): `skills/commit/SKILL.md:250` (was `:169`), `skills/do/modes/direct.md:18`, `skills/do/SKILL.md:342`, `skills/doc/SKILL.md:282`, `skills/doc/SKILL.md:314`, `skills/fix-issues/SKILL.md:777` (was `:755`), `skills/fix-issues/SKILL.md:1130` (was `:1090`), `skills/qe-audit/SKILL.md:283`.
    - **`npm start` PROSE-IMPERATIVE site** (refine-2 DA2.10 — was missed in earlier enumeration): `skills/verify-changes/SKILL.md:687` reads `Run \`npm start &\` — it takes 2 seconds.` Bullet (`-`) + code-span + sentence-start `Run` = textbook PROSE-IMPERATIVE. Migrates to `Run \`$DEV_SERVER_CMD &\`` (with the substitution-discipline note added per the convention below).
    - **Implementing agent re-derives** with: `grep -nE 'npm run test:all' skills/ -r | grep -E '^[^:]+:[^:]+:[[:space:]]*[-*0-9]' | grep -iE 'Run|Execute|Invoke' | grep -F '\`npm run test:all\`'` (sentence-start anchoring matches Phase 4.1 detection regex per refine-2 DA2.9). Same form for `npm start`. Then manually classify each hit (bullet/numbered + sentence-start imperative-verb + code-span = PROSE-IMPERATIVE; descriptive sentence about running tests = PROSE-DESCRIPTIVE → out of scope per Overview line "Verified DESCRIPTIVE").
    - For each PROSE-IMPERATIVE hit: replace the literal in the prose code-span with `$FULL_TEST_CMD` (or `$DEV_SERVER_CMD` for `npm start`). Match `skills/run-plan/SKILL.md:181` convention.

    **Substitution-discipline coverage outside /run-plan** (refine-2 R2.12). The model-side `$VAR` substitution discipline is currently documented only at `skills/run-plan/SKILL.md:181-185` (and strengthened in this plan's INJECTED-BLOCKQUOTE migration above). PROSE-IMPERATIVE sites in `commit/SKILL.md`, `do/SKILL.md`, `doc/SKILL.md`, `fix-issues/SKILL.md`, `qe-audit/SKILL.md`, `verify-changes/SKILL.md` (8 sites total) do NOT inherit `/run-plan`'s prose context — when a model READS those skills directly (not as an orchestrator dispatching from /run-plan), the bare `$FULL_TEST_CMD` reference may be emitted literally as `$FULL_TEST_CMD` rather than resolved.

    Resolution: each PROSE-IMPERATIVE migration site adopts ONE of two forms (implementing agent picks per site based on local prose context):

    (a) **Inline resolution-discipline annotation.** Replace the literal with `$FULL_TEST_CMD` AND append a parenthetical: "Run `$FULL_TEST_CMD` (resolve via `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh" && echo $FULL_TEST_CMD` if you don't already have it in your environment)." Heavyweight; use only when the surrounding skill has no other config-resolution context.

    (b) **Per-skill canonical-prelude reference.** If the skill already has a "Read this config first" block earlier in its prose (existing pattern in `commit/SKILL.md:68`, `fix-issues/SKILL.md:99,111`, `quickfix/SKILL.md:138`, `run-plan/SKILL.md:97-176`), the PROSE-IMPERATIVE site references it: "Run `$FULL_TEST_CMD` (resolved per the config-read block at line N above)." Lightweight; use when prose context already establishes the discipline.

    Form (b) is preferred where applicable. The implementing agent inspects each of the 9 PROSE-IMPERATIVE sites (8 + verify-changes:687) and picks (a) or (b) per site. Phase 5 WI 5.2's positive-side regex catches the file-global helper-source presence; Phase 5 WI 5.7 (NEW — refine-2 R2.12) adds a per-site assertion that EACH PROSE-IMPERATIVE-migrated line is followed within 5 lines by either the canonical-prelude pointer or the inline resolution-discipline annotation.

  - **INJECTED-BLOCKQUOTE migration — `skills/run-plan/SKILL.md:898-930` (refine-1 R1.5; refine-2 R2.1/R2.2/R2.8/DA2.1/DA2.2/DA2.3 architectural reframe)**. The blockquote is declared "VERBATIM-injected into every implementation and verification agent prompt" by the orchestrator. It contains literal `npm start &` (line 903), `$TEST_OUT/.test-results.txt` (lines 909, 916, 925), and `$FULL_TEST_CMD` (lines 909, 919, 925).

    **Architecture chosen (refine-2):** the orchestrator IS the model executing /run-plan — there is NO bash code path in `skills/run-plan/SKILL.md` that emits the dispatch prompt; dispatch is agent-internal (the model reads "Include this VERBATIM..." at line 900 and types the blockquote into the subagent's prompt). The refine-1 `__SNAKE__` + `sed` pre-emission mechanism specified a host fence that does not exist (verified `grep -rn 'RAW_RECIPE\|RECIPE_TEXT\|__DEV_SERVER_CMD__\|__TEST_OUTPUT_FILE__' skills/` → 0 hits; refine-2 R2.1/DA2.1) and would also break on `|` characters in config values (verified empirically: `DEV_SERVER_CMD='yarn start | tee output.log'; sed -e "s|__DEV_SERVER_CMD__|${DEV_SERVER_CMD}|g"` → `sed: unknown option to 's'`; refine-2 DA2.3). The mechanism is therefore **dropped entirely**.

    **Replacement: leverage the existing model-side substitution discipline at `skills/run-plan/SKILL.md:181`.** The skill already documents (post-Phase 2 `$FULL_TEST_CMD` migration): "Agent dispatch prompts must include the resolved `$FULL_TEST_CMD` literal ... so the dispatched agent does not search the repo for a test script." This is a working convention — `$FULL_TEST_CMD` already appears in the blockquote at lines 909, 919, 925, and the orchestrator-model already resolves+substitutes it before emission. The migration extends this discipline to two more vars.

    Concrete edits to `skills/run-plan/SKILL.md`:

    - **Line 903** — `Start a dev server FIRST: \`npm start &\`` → `Start a dev server FIRST: \`$DEV_SERVER_CMD &\``
    - **Lines 909, 925** — `$FULL_TEST_CMD > "$TEST_OUT/.test-results.txt" 2>&1` → `$FULL_TEST_CMD > "$TEST_OUT/$TEST_OUTPUT_FILE" 2>&1`
    - **Line 916** — `**read \`"$TEST_OUT/.test-results.txt"\`**` → `**read \`"$TEST_OUT/$TEST_OUTPUT_FILE"\`**`
    - **Lines 909, 919, 925** `$FULL_TEST_CMD` references stay as-is (already convention-aligned).

    **Strengthen the substitution-discipline instruction.** Edit `skills/run-plan/SKILL.md:181-185` (the "Never hardcode `npm run test:all`..." paragraph) to enumerate ALL three vars whose dispatch-prompt resolution is required:

    ```
    **Never hardcode `npm run test:all`, `npm start`, or `.test-results.txt`.**
    Every subsequent reference uses `$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, and
    `$TEST_OUTPUT_FILE`. **Agent dispatch prompts must include the RESOLVED
    literal value** of each var (substituted from the helper's output BEFORE
    emission), or the explicit "Tests: skipped — no test infra" when
    `TEST_MODE=skipped`. Markdown blockquotes (e.g., the worktree-test recipe
    at lines 898-930) do NOT undergo parameter expansion at emission time —
    YOU, the orchestrator-model, must perform the substitution before typing
    the blockquote into the subagent's prompt.
    ```

    Also add — in the bash fence at lines 144-176 (the three-case test-mode tree) where `$FULL_TEST_CMD` is resolved — a sibling resolution for `$DEV_SERVER_CMD` and `$TEST_OUTPUT_FILE` from the helper (one-line preamble + `[ -z "$DEV_SERVER_CMD" ] && DEV_SERVER_CMD=npm` informational fallback for the recipe; `[ -z "$TEST_OUTPUT_FILE" ] && TEST_OUTPUT_FILE=.test-results.txt` informational fallback). This makes the resolved literals available in the orchestrator-model's working memory by the time it constructs the dispatch prompt.

    **Critical-path empty-handling.** `$FULL_TEST_CMD` empty triggers fail-closed via the existing three-case tree at lines 144-176. `$DEV_SERVER_CMD` empty: informational fallback to `npm start` documented in the skill prose ("if `dev_server.cmd` is unset, the recipe instructs `npm start` as a sensible default; configure `dev_server.cmd` for non-npm projects"). `$TEST_OUTPUT_FILE` empty: informational fallback to `.test-results.txt` (filename suffix not load-bearing for project semantics).

    **Enforcement of this site is in Phase 4 (WI 4.1 blockquote-aware deny-list + WI 4.6 structural AC).** The deny-list pseudocode strips leading `>[[:space:]]*` from each blockquote line before applying the fence-opener / bullet-list / imperative-verb regexes — see Phase 4.1 for the updated detection logic. A new Phase 4.6 structural AC asserts that the blockquote text at `skills/run-plan/SKILL.md:898-930` contains only `$VAR` references (no raw literals like `npm start`, `npm run test:all`, or `.test-results.txt` that aren't preceded by `$`).

  - **co_author migration — 2 sites + verify schema/install present**: `skills/commit/SKILL.md:291` (was `:210` per stale plan citation; refine-1 R1.4), `skills/quickfix/SKILL.md:603`. Currently both hardcode `CO_AUTHOR="Claude Opus 4.7 (1M context) <noreply@anthropic.com>"` then override from config. The 3 additional `CO_AUTHOR=` BASH_REMATCH assignments at `commit/SKILL.md:295`, `quickfix/SKILL.md:605`, `update-zskills/SKILL.md:222` are extraction-side logic and stay in place (or, if the helper supplants them, are removed alongside the hardcoded default). Migration:
    - **Skills drop their hardcoded defaults entirely.** Source the helper at fence-top (already covered by 1-line preamble); use `$COMMIT_CO_AUTHOR` from the helper's resolution.
    - **Conditional trailer emission.** co_author is **informational metadata**, not critical-path — the Co-Authored-By trailer is optional. Skills append the trailer ONLY if `$COMMIT_CO_AUTHOR` is non-empty:

      ```bash
      if [ -n "$COMMIT_CO_AUTHOR" ]; then
        # append "Co-Authored-By: $COMMIT_CO_AUTHOR" to commit body
      fi
      ```

      No fail-loud on empty: blank value is a valid consumer opt-out (some downstreams may not want AI attribution in commit logs).
    - **Schema-default carries the version-specific identity.** `config/zskills-config.schema.json` (source-of-truth — NOT `.claude/zskills-config.schema.json` which is the consumer-installed copy generated by `/update-zskills`; refine-2 R2.3 fix to align with Phase 1 WI 1.2's correction) sets the default for `commit.co_author` to `"Claude Opus 4.7 (1M context) <noreply@anthropic.com>"` (verified at line 55). /update-zskills writes this default on fresh install AND backfills it into existing configs that lack the field (standard backfill behavior per DRIFT_ARCH_FIX Phase 2 convention; backfill verified at `skills/update-zskills/SKILL.md:226-234`). When Anthropic releases a new Claude version, zskills bumps the schema default; downstream `/update-zskills --rerender` (or next install) propagates the new value.
    - **Three resulting consumer states (per the design table):**
      - Field absent in config → /update-zskills backfills with schema default → trailer uses default
      - Field set to custom value → trailer uses custom
      - Field set to `""` (blank) → no trailer (consumer opt-out, intentional bypass)

  - **`scripts/port.sh` reference migration — REMOVED FROM SCOPE (refine-1 R1.3 / DA1.1).** All 5 originally-cited sites already use the post-SCRIPTS_INTO_SKILLS_PLAN runtime path on current main; no migration work remains. See WI 2.1 note. Verified by `grep -rE 'bash scripts/port\.sh|\(scripts/port\.sh\)' skills/` returning 0 hits as of refine-1.

  - **`testing.output_file` migration — 16 sites** (refine-1 R1.2 — line numbers will drift; re-derive at execution time via `grep -rnE '\$TEST_OUT/\.test-results\.txt' skills/`; refine-2 DA2.11 added `investigate:210` to reads list which was missed in refine-1):
    - **EXEC-FENCE writes (7)**: `skills/investigate/SKILL.md:208`, `skills/quickfix/SKILL.md:546`, `skills/run-plan/SKILL.md:909` (INJECTED-BLOCKQUOTE — see above), `skills/run-plan/SKILL.md:925` (INJECTED-BLOCKQUOTE), `skills/run-plan/SKILL.md:1205`, `skills/verify-changes/SKILL.md:307`, `skills/verify-changes/SKILL.md:349`.
    - **EXEC-FENCE reads (7)**: `skills/investigate/SKILL.md:210` (refine-2 DA2.11), `skills/quickfix/SKILL.md:547`, `skills/run-plan/SKILL.md:916` (INJECTED-BLOCKQUOTE), `skills/run-plan/SKILL.md:1240`, `skills/verify-changes/SKILL.md:310`, `skills/verify-changes/SKILL.md:314`, `skills/verify-changes/SKILL.md:334`.
    - **MODE-FILE comments (2)**: `skills/run-plan/modes/pr.md:491,495`.
    - Total 7+7+2 = 16, matches anchored `grep -rnE '\$TEST_OUT/\.test-results\.txt' skills/` count. Two additional non-anchored prose hits (`skills/run-plan/SKILL.md:820`, `skills/update-zskills/SKILL.md:276`) contain bare `.test-results.txt` without the `$TEST_OUT/` prefix — out of scope (PROSE-DESCRIPTIVE / schema-default content respectively; not a hardcode in any executable surface).

    Each EXEC-FENCE site (NOT the 3 INJECTED-BLOCKQUOTE sites — those use bare `$TEST_OUTPUT_FILE` references per the INJECTED-BLOCKQUOTE sub-bullet's model-side substitution discipline; refine-2 R2.1 architectural reframe replaced the earlier `__SNAKE__` markers): source the helper at fence-top (already covered by preamble); replace `$TEST_OUT/.test-results.txt` with `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}`. Informational consumer — fall back to literal `.test-results.txt` if config empty since the filename suffix isn't load-bearing for project semantics.

  - **EXEC TZ migration — 60 sites across 16 files at refine-1 grep time** (refine-1 R1.2, R1.8). Implementing agent re-derives at execution time. Sites known at refine-1:
    - **Original audit set (from refine round 3):** `skills/run-plan/SKILL.md` (10), `skills/fix-issues/SKILL.md` (9), `skills/run-plan/modes/pr.md` (6), `skills/verify-changes/SKILL.md` (5), `skills/draft-plan/SKILL.md` (5), `skills/refine-plan/SKILL.md` (4), `skills/fix-issues/modes/direct.md` (4), `skills/fix-issues/modes/pr.md` (3), `skills/fix-issues/modes/cherry-pick.md` (2), `skills/do/modes/pr.md` (2), `skills/run-plan/modes/cherry-pick.md` (1), `skills/quickfix/SKILL.md` (1), `skills/fix-issues/references/failure-protocol.md` (1), `skills/commit/modes/land.md` (1).
    - **NEW post-2026-04-25 (refine-1 R1.8):** `skills/work-on-plans/SKILL.md` (5 sites at `:583,594,643,672,1143` — all `printf ... "$(TZ=America/New_York date -Iseconds)" \` marker-write idiom), `skills/zskills-dashboard/SKILL.md` (1 site at `:158` — `printf 'date: %s\n' "$(TZ=America/New_York date -Iseconds)"`). Same migration pattern as fix-issues/draft-plan/refine-plan.

    Each: source the helper at fence-top; replace `TZ=America/New_York` with `TZ="${TIMEZONE:-UTC}"` (informational; UTC fallback). The subshell form `$(TZ=America/New_York date -Iseconds)` becomes `$(TZ="${TIMEZONE:-UTC}" date -Iseconds)`.

  - **Quoted heredocs (`<<'TAG'`)** — if 2.1's enumeration found any in the migration set: capture the resolved value into a shell var BEFORE the heredoc opener; embed the literal value into the heredoc body. (Expected count: 0.)

- [ ] 2.3 — **Mirror sync.** For every modified file in `skills/`, `cp` to `.claude/skills/`; verify with `diff -q` (silent = pass). Per `feedback_claude_skills_permissions`, batch the `cp` calls — don't intersperse with Edits.

- [ ] 2.4 — **Categorized re-audit.** Run the same grep as the original audit. Each hit must be in PROHIBITION or MIGRATION-TOOL or PROSE-DESCRIPTIVE category, NOT EXEC-FENCE. Document remaining-hit count per category in the phase report. Legitimate remaining literals (prohibition-by-name in `run-plan/SKILL.md:179`, migration-tool literal in `update-zskills/SKILL.md:404`) are expected. Resolves DA1.11.

- [ ] 2.5 — **End-to-end fixture test** (refine-2 DA2.20 mechanism specified). Add `tests/test-skill-file-drift.sh` (new file; following the existing `tests/run-all.sh` driver convention plus the per-test format used in `tests/test-update-zskills-rerender.sh`). The test:

  1. Sets up a temp dir under `/tmp/zskills-tests-fixture-$$/` with `.claude/zskills-config.json` containing `timezone: "Europe/London"`, `testing.full_cmd: "FIXTURE_FULL"`, `dev_server.cmd: "FIXTURE_DEV"`, `testing.output_file: "FIXTURE_OUT.log"`, `commit.co_author: "Fixture <fixture@example.com>"`.
  2. Sets `CLAUDE_PROJECT_DIR=$temp_dir` (consistent with `tests/run-all.sh:7` export pattern).
  3. **Inline-extracted reference fence** — picks a small representative migrated fence rather than parsing markdown for fence extraction. Recommended source: `skills/draft-plan/SKILL.md` (after Phase 2 migration, the fence at the start that opens with `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"` then prints a TZ-marker). Hand-copy the relevant fence content into a heredoc inside the test script — DO NOT auto-extract from the source SKILL.md (extraction adds an own-tail of grep/sed/awk regex that would itself be a drift surface). Update the test heredoc when the reference fence's structure changes (rare; flagged by mirror-parity diff if it happens).
  4. Executes the heredoc'd fence under `bash` and captures stdout.
  5. Asserts the captured output contains `Europe/London` (TZ resolved), `FIXTURE_FULL` (test-cmd resolved), and `FIXTURE_OUT.log` (output-file resolved). Asserts it does NOT contain `New_York`, `npm run test:all`, or `.test-results.txt` literally (which would mean the migration didn't take effect).
  6. Failure messages: `FAIL: tests/test-skill-file-drift.sh case <N>: expected <X> in output, got <Y>`. Pattern matches `tests/test-update-zskills-rerender.sh` failure-message format.
  7. Cleanup at end: `rm -rf "$temp_dir"`.

  Resolves DA2.10 / R2 round-2 concerns about cross-downstream behavior, and DA2.20's request for explicit harness mechanism.

### Design & Constraints

**Migration discipline.** Each diff hunk should be the one-line preamble + literal substitution + empty-check guard. Do NOT reformat surrounding prose, change unrelated lines, or "improve" adjacent code.

**Per-fence cost.** ONE line per fence (preamble) + 1 line per literal substitution + 4 lines per critical-path empty-check. With **~67 affected fences** (refine-1 R1.11 — re-derived via fence-state awk pass; previous "~40" estimate was pre-refine-3-scope-expansion), total new boilerplate: ~67 + ~96 + ~32 ≈ **~195 lines added** across the migration. Compares to ~1000 lines under the rejected inline-block design. Reviewer-fatigue mitigation argument still holds.

**Critical-path vs informational empty-handling.** Test-cmd and dev-server-cmd are critical (gate operations); empty config means fail-closed with explicit `/update-zskills` pointer. Timezone is informational (timestamp formatting); empty means UTC fallback with no error. Phase 1.3 documents both patterns; Phase 2.2 picks per literal.

**No allowlist exemptions added in Phase 2.** Every EXEC-FENCE hit is migrated. Phase 4 sets up the allowlist convention for legitimate prohibition-by-name / migration-tool sites that already exist.

**Inline config-read blocks are out of scope** (refine-1 R1.10). 6 inline `CONFIG_CONTENT=$(cat ".claude/zskills-config.json")` blocks exist (`skills/commit/SKILL.md:68,293`, `skills/fix-issues/SKILL.md:99,111`, `skills/draft-plan/SKILL.md:220`, `skills/quickfix/SKILL.md:138`, `skills/run-plan/SKILL.md:97,115,130,147`, `skills/update-zskills/SKILL.md:172`) each with their own bash regex extraction. They are NOT migrated by this plan because: (a) they pre-date the helper, (b) the three-case test-mode tree at `skills/run-plan/SKILL.md:144-176` has gate-decision logic the helper deliberately does not replicate, and (c) migrating them risks scope creep mid-plan. Follow-up: file an issue to consolidate via the helper once migration has shipped and stabilized.

**`.test-baseline.txt` decision (refine-1 R1.6; refine-2 R2.10 rationale corrected).** The plan adds `testing.output_file` to the helper. A sibling filename `.test-baseline.txt` is also hardcoded in the codebase (`skills/run-plan/SKILL.md:821,1052,1237,1239,1247`, `skills/commit/scripts/land-phase.sh:61`'s `EPHEMERAL_FILES` list). Decision: **the baseline filename is OUT OF SCOPE for this plan.**

  Rationale (refine-2 R2.10 sharpened — the earlier rationale conflated two distinct coupling kinds; the hook embeds `.test-results.txt` only in suggestion-message TEXT, not in detection logic):

  (a) `.test-results.txt` is the runtime test-output sink — the migration's primary surface.

  (b) `.test-baseline.txt` is captured ONCE per phase before implementation begins (run-plan-internal idiom) and isn't user-configurable in any meaningful sense.

  (c) Coupling it to `testing.output_file` would conflate two distinct lifecycle artifacts.

  (d) The **canary in `land-phase.sh:61`** is genuinely coupled to the literal — its `EPHEMERAL_FILES=(".test-results.txt" ".test-baseline.txt" ...)` list IS detection logic. Making `.test-results.txt` configurable would require updating the canary list to read the same `testing.output_file` config field, OR extending the canary to a wildcard pattern.

  (e) The **hook at `block-unsafe-project.sh:311`** embeds `.test-results.txt` only in suggestion-message text (the `block_with_reason "Don't pipe test output ... ${FULL_TEST_CMD:-npm run test:all} > \"\$TEST_OUT/.test-results.txt\" 2>&1 then read..."` argument). This is NOT detection — pipe-detection runs via `TEST_PIPE_PATTERN` regardless of filename. Downstream that configures `output_file: .out.log` still has its pipe-blocking work correctly; only the suggestion message becomes inaccurate (cosmetic, not safety-relevant). DA2.13 calls out that Phase 3 should also fix the message text to reference `${TEST_OUTPUT_FILE:-.test-results.txt}` (handled in Phase 3 WI 3.1 — see refine-2 DA2.13 fix).

  The decision to keep `.test-baseline.txt` OUT OF SCOPE rests primarily on (b) and (d) — its independent purpose (per-phase baseline, not user-configurable) and the canary coupling. (e)'s message-text inaccuracy is cosmetic and addressed independently. Document the decision as a known limitation in `references/canonical-config-prelude.md` ("file `.test-baseline.txt` is intentionally not user-configurable; it is a run-plan-internal phase-baseline artifact"). If a future need arises, file a follow-up plan with a `testing.output_filenames: { results, baseline }` design pattern.

### Acceptance Criteria

- [ ] **Mechanical re-audit** (refine-2 DA2.15 — replaces earlier prose-classification ACs). The categorical re-audit IS Phase 4.1's deny-list test: `bash tests/run-all.sh` runs `tests/test-skill-conformance.sh` which includes the deny-list section. After Phase 2 lands AND Phase 4.1's empty-fixture test has been progressively populated (per WI 4.7), the deny-list test passes — that PASS is the categorical-re-audit verification. The earlier "manually classify each remaining hit" phrasing left the AC unmechanizable (no test fails CI when an unmarked EXEC-FENCE hit slips through unless 4.1 catches it; 4.1 IS the test, so the phrasing was circular). Concrete check:

  ```bash
  bash tests/test-skill-conformance.sh && echo "Phase 2 categorical re-audit: PASS"
  ```

  Plus the **structural blockquote AC** (Phase 4 WI 4.6) which ALSO lands as part of Phase 4 strict-after-Phase-2 ordering and verifies the load-bearing INJECTED-BLOCKQUOTE site specifically. The recipe blockquote at `skills/run-plan/SKILL.md:898-930` contains only `$VAR` references (no raw `npm start`/`npm run test:all`/`.test-results.txt`); WI 4.6 enforces this structurally.
- [ ] `find skills -name '*.md' | while read f; do diff -q "$f" ".claude/$f"; done` returns no diffs (mirror parity; refine-1 R1.20 — `find` form, not `**/*.md` globstar which is bash-version-dependent).
- [ ] `bash tests/run-all.sh` passes (1212 baseline at refine-1 + new from Phase 1; agent re-derives count at execution).
- [ ] **Synthetic-fixture test** that exercises a migrated mode-file fence with `timezone: "Europe/London"` config and confirms the resulting timestamp uses London time, not New York.
- [ ] **Blockquote-structural AC (refine-2 R2.8 reframe):** since the refine-1 `__SNAKE__`/sed mechanism was dropped (no host fence; refine-2 R2.1) in favor of model-side `$VAR` substitution discipline (matching the existing `$FULL_TEST_CMD` convention at `skills/run-plan/SKILL.md:181`), the AC becomes structural rather than emission-simulation: assert the markdown source of `skills/run-plan/SKILL.md:898-930` contains ONLY `$VAR`/`${VAR}` references, NO raw literals. Concrete grep:

  ```bash
  # Extract blockquote bounds (line range), then grep for forbidden literals.
  awk '/^[[:space:]]*> \*\*Worktree test recipe:\*\*/,/^[[:space:]]*8\. \*\*No steps skipped/' \
      skills/run-plan/SKILL.md > /tmp/blockquote.txt
  ! grep -E 'npm start|npm run test:all|\.test-results\.txt' /tmp/blockquote.txt \
      || { echo "FAIL: raw literal in worktree-test blockquote"; exit 1; }
  grep -qE '\$DEV_SERVER_CMD' /tmp/blockquote.txt || { echo "FAIL: \$DEV_SERVER_CMD missing"; exit 1; }
  grep -qE '\$TEST_OUTPUT_FILE' /tmp/blockquote.txt || { echo "FAIL: \$TEST_OUTPUT_FILE missing"; exit 1; }
  grep -qE '\$FULL_TEST_CMD' /tmp/blockquote.txt || { echo "FAIL: \$FULL_TEST_CMD missing"; exit 1; }
  ```

  This is mechanical (no orchestrator simulation needed) and runs in `tests/test-skill-conformance.sh`. Live-emission verification (does the orchestrator-model actually substitute? does the dispatched subagent receive the resolved string?) is covered by the integration smoke test in Phase 5 WI 5.6 (new — see Phase 5).

### Dependencies

Phase 1 (canonical block must exist as a reference; inlining rule must be documented).

## Phase 3 — Fix `block-unsafe-project.sh:311` Opinionated Fallback + Sync Test-Infra Detection

### Goal

Remove the npm-specific fallback at `block-unsafe-project.sh:311` (verified present at commit f00e7c1). Adopt the three-case test-infra-detection tree that `verify-changes/SKILL.md` uses, and add a sync test asserting both consumers stay aligned.

### Work Items

- [ ] 3.1 — **Sweep ALL `${VAR:-default}` opinionated fallbacks in hooks** (refine round 3 anti-deferral). Run `grep -nE '\$\{[A-Z_]+:-[^}]+\}' hooks/*.template .claude/hooks/*.sh` to enumerate every parameter-expansion-with-default in the hook layer. For each hit: classify whether the default is opinionated (npm-specific, hardcoded path, etc.) or sensible (UTC timezone, empty string). Opinionated defaults get replaced with empty-string + three-case-tree. Currently-known instance: `block-unsafe-project.sh:311` `${FULL_TEST_CMD:-npm run test:all}`. Document any others found in the Phase 3 report; each gets its own three-case-tree fix (or substantively different justification, NOT "out of scope"). Remove the `:-npm run test:all` fallback and any other opinionated defaults; replace with empty-string default `${FULL_TEST_CMD}`. Mirror to `.claude/hooks/`.

  **Also fix the `.test-results.txt` literal in the same line's suggestion-message text** (refine-2 DA2.13). The same line at `block-unsafe-project.sh:311` (and its template counterpart) embeds `\"\$TEST_OUT/.test-results.txt\"` literally in the `block_with_reason` argument — message text, not detection logic (per refine-2 R2.10 disambiguation), but the suggestion will mislead a downstream that configures `output_file: .out.log` into looking for a file that doesn't exist. Resolve via the same helper sourcing pattern Phase 2 uses elsewhere: source `zskills-resolve-config.sh` near the top of the hook (one-line preamble, with the existing `[ -r "$FIXTURE_PATH" ] || exit 0`-style graceful-degradation guard for downstream installs that bypass /update-zskills), then substitute `\"\$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}\"` in the suggestion-message text. Test in WI 3.5 (Case A): with `testing.output_file: ".out.log"` configured, the block-message includes `.out.log` not `.test-results.txt`.

- [ ] 3.2 — **Implement the three-case tree** at the test-pipe gate (and any other gate that consumed the fallback):
  - **Case A — `FULL_TEST_CMD` set**: gate operates as today.
  - **Case B — `FULL_TEST_CMD` empty AND no test infra detected**: skip the gate. Log `# /verify-changes: no test infra detected; test-pipe gate disabled` to stderr.
  - **Case C — `FULL_TEST_CMD` empty BUT test infra detected**: deny with explicit error pointing at `/update-zskills`.

  Test-infra detection list (mirrors `skills/verify-changes/SKILL.md:80-105`): package.json with a `"test"` script; `vitest.config.*`, `jest.config.*`, `pytest.ini`, `.mocharc.*`; `Makefile`; `tests/*.sh`, `tests/*.py`, `tests/*.js`.

- [ ] 3.3 — **Mirror to `.claude/hooks/block-unsafe-project.sh`.** Verify with `diff -q hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh`.

- [ ] 3.4 — **Test-infra detection sync.** The two consumers encode the list differently (markdown prose with examples vs bash conditional chain), so a strict text-diff test would always fail. Instead: extract a **canonical pattern set** to a shared file `tests/fixtures/test-infra-patterns.txt` (one pattern per line: `package.json`, `vitest.config.*`, `jest.config.*`, `pytest.ini`, `.mocharc.*`, `Makefile`, `tests/*.sh`, `tests/*.py`, `tests/*.js`). Then:
  - Add a test in `tests/test-hooks.sh` that greps `block-unsafe-project.sh` for each line of the fixture file and asserts each pattern appears (in any form — bash conditional, comment, doc-string).
  - Add a test (or extend existing test-skill-conformance.sh) that greps `verify-changes/SKILL.md` for each fixture line and asserts each appears.
  - Failure message: `Test-infra detection list missing pattern <X> in <file>. Update <file> or remove from tests/fixtures/test-infra-patterns.txt.`

  Resolves DA1.6 + R2.3 (sync-test methodology was previously vague).

- [ ] 3.5 — **Add three test cases for WI 3.2** in `tests/test-hooks.sh` (Case A, B, C) using fixture-based testing per DRIFT_ARCH_FIX Phase 1 WI 1.5 pattern (temp dir + synthetic config + `REPO_ROOT=` env override).

### Design & Constraints

**Why this is in scope despite being a CODE consumer DRIFT_ARCH_FIX touched.** DRIFT_ARCH_FIX migrated the variable's source (config-read at runtime). It did NOT audit the variable's consumer — the `:-npm run test:all` fallback survived. The fix shares the three-case-tree design with `verify-changes`, so closing it standalone would duplicate the design exposition. Phase 3 closes it here.

**Test-infra detection list maintenance.** WI 3.4 adds a sync assertion via `tests/fixtures/test-infra-patterns.txt` (single-source-of-truth file). The two consumers (`block-unsafe-project.sh`, `verify-changes/SKILL.md`) each get tested against the canonical fixture. SCRIPTS_INTO_SKILLS_PLAN provides install infrastructure for shared fixture files, so the install-dependency objection that motivated inline duplication is no longer load-bearing (refine round 3 R3.1 / DA3.3).

### Acceptance Criteria

- [ ] `grep -F ':-npm run test:all' hooks/ .claude/hooks/` returns 0 hits.
- [ ] Three new test cases in `tests/test-hooks.sh` cover Cases A, B, C with fixture-based assertions.
- [ ] One new sync test asserts test-infra detection list parity between `block-unsafe-project.sh` and `verify-changes/SKILL.md`. Failing the sync test on a fixture (synthetic divergence) produces the expected error message.
- [ ] `bash tests/run-all.sh` passes.

### Dependencies

Phase 1 (canonical block referenced by the empty-handling docs; three-case tree referenced from the canonical-prelude doc).

## Phase 4 — Enforcement

### Goal

Prevent new hardcodes from re-accumulating. Three layers, each catching a different gap.

### Work Items

- [ ] 4.1 — **Test deny-list** in `tests/test-skill-conformance.sh`. New section `=== No skill-file drift hardcodes ===`. **Single source of truth**: literal list lives in `tests/fixtures/forbidden-literals.txt` (one literal per line; comments allowed via `#` prefix). Both the test (WI 4.1) AND the drift-warn hook (WI 4.2) read from this file at runtime. The fixture-file approach is the same pattern as Phase 3.4's `tests/fixtures/test-infra-patterns.txt` (resolves DA1.5 / refine-DA1.5).

  **Post-refine-1 fixture contents** (4 entries — refine-1 R1.13 dropped `scripts/port.sh` per R1.3; refine-1 DA1.5 reframes `.test-results.txt` as anchored regex pattern to avoid colliding with the migration's own fallback default):
  ```
  TZ=America/New_York
  npm run test:all
  npm start
  \$TEST_OUT/\.test-results\.txt
  ```

  **Note on the `.test-results.txt` entry (refine-1 DA1.5).** The deny-list entry uses an **anchored regex pattern** `\$TEST_OUT/\.test-results\.txt` (not a substring), so the fixture-driven matcher requires the `$TEST_OUT/` prefix. This avoids false-positives against the migration's own fallback default `${TEST_OUTPUT_FILE:-.test-results.txt}` (which contains the substring `.test-results.txt` but is the migration target, not a hardcode). Verified by greping `\$TEST_OUT/\.test-results\.txt` against the post-migration codebase: matches only EXEC-FENCE drift sites, not the substituted fallback expressions. The fixture-reader (Phase 4.1 pseudocode + Phase 4.2 hook) MUST treat this entry as a regex (`grep -E`) rather than a fixed string — see the pseudocode/hook code for the dispatch.

  Other entries (`TZ=America/New_York`, `npm run test:all`, `npm start`) remain as fixed-substring matches because their substring presence in any context indicates a hardcode.

  **Fixture format (refine-1 fix; refine-2 R2.5/R2.6/R2.13/DA2.22 hardening):** Each line is either a literal substring (default) OR — if it begins with `re:` — a regex pattern. Recommended format for clarity:
  ```
  TZ=America/New_York
  npm run test:all
  npm start
  re:\$TEST_OUT/\.test-results\.txt
  ```
  The fixture-reader parses each line: lines starting with `re:` are regexes (via `grep -E`), others are fixed substrings (via `grep -F`). Comments (lines starting with `#`) and blank lines skipped.

  **`re:` prefix collision** (refine-2 R2.5/DA2.22): forbidden literals starting with the substring `re:` cannot be deny-listed in literal mode (the prefix would be stripped and the rest treated as regex). Currently no forbidden literal triggers this collision. If one ever does, express it as a regex with a literal-`re:` prefix in the pattern, e.g., `re:re:remote` denies the literal substring `re:remote`. Documented for future-proofing.

  **Regex-anchoring discipline** (refine-2 R2.13): bash `[[ =~ ]]` is unanchored — a regex like `\$TEST_OUT/\.test-results\.txt` matches the substring even if surrounded by other characters. Authors of `re:` entries are responsible for adding `^`/`$`/word-boundary anchors as needed. The current sole regex `\$TEST_OUT/\.test-results\.txt` is acceptable because `$TEST_OUT/` is a strong-enough natural anchor (no realistic prefix), but new `re:` entries MUST self-anchor or document why an unanchored match is correct.

  **Allowlist marker semantics for regex entries** (refine-2 R2.6): when exempting a regex deny-list entry via the inspectable allowlist marker, the marker's `<literal>` token is the regex pattern WITHOUT the `re:` prefix — same string the pseudocode uses as the `allowed_in_fence` key. Example: `<!-- allow-hardcoded: \$TEST_OUT/\.test-results\.txt reason: migration-tool literal -->` exempts the regex deny-list entry `re:\$TEST_OUT/\.test-results\.txt`. A worked example for a regex-entry exemption appears in Phase 4.4's `.claude/rules/zskills/managed.md` documentation.

  **Detection runs in TWO modes** (both blockquote-aware per refine-2 R2.2/DA2.2/DA2.8 — strip leading `>` + whitespace from each line BEFORE applying any of the regexes below; see pseudocode):
  - **EXEC-FENCE detection** (default): hits inside ` ```bash `/`sh`/`shell` fences flagged unless an `<!-- allow-hardcoded -->` marker exempts them. Uses fence-state pseudocode below. **Blockquote-prefixed fences** (` >    \`\`\`bash`) ARE matched after `>`-stripping — this is load-bearing for the recipe blockquote at `skills/run-plan/SKILL.md:898-930` (refine-2 R2.2/DA2.2/DA2.8: empirical regex test confirms the un-stripped fence-opener regex `^[[:space:]]*\`\`\`(bash|sh|shell)?[[:space:]]*$` does NOT match `   >    \`\`\`bash`).
  - **PROSE-IMPERATIVE detection** (refine round 3, hardened in refine-2 DA2.9): hits in PROSE outside fences, when the literal appears inside a code-span ` ` ` ` ` AND the line begins with a bullet (`^[[:space:]]*[-*]`) or numbered-list marker (`^[[:space:]]*[0-9]+\.`) AND contains an **upper-case-anchored** imperative verb at sentence-start position: `(^|[.;:][[:space:]]+|\*\*)(Run|Execute|Invoke)\b` (refine-2 DA2.9: lower-case `run` matched past-participle "has run" / "can run" producing FPs verified empirically — `'- The user can run \`npm run test:all\`'` flagged as imperative). Same allowlist marker mechanism applies. Blockquote prefix `>` is stripped before applying the bullet/imperative regexes too — load-bearing for `verify-changes/SKILL.md:687`-style hits if they ever migrate into a blockquote, and for any future blockquote that contains run-style imperatives.

  For each literal in the fixture:
  - Grep recursively across `skills/**/*.md` (NOT `.claude/skills/*` — those are mirrors).
  - **Skip prose contexts**: only flag hits inside ` ```bash ` (or ` ```sh `, ` ```shell `, or ` ``` ` no-language) fences. Track fence state by line.
  - **Allowlist marker scope** (refined post-refine-DA1.3): the marker `<!-- allow-hardcoded: <literal> reason: ... -->` lives in MARKDOWN PROSE on the line IMMEDIATELY ABOVE a fence-opener. Such a marker exempts ALL hits of `<literal>` inside the immediately-following fence. The marker MUST NOT appear inside a fence (HTML comments aren't bash-valid and the test's expected scope is prose). Per-line markers (same-line or single-line-above the literal) are NOT supported — fence-scoped is simpler and matches realistic use cases (legitimate in-fence literals come in clusters: migration-tool greps, synthetic fixtures).

    Pseudocode:

    Pseudocode (post-refine-2 fixes — strips blockquote `>` prefix per R2.2/DA2.2/DA2.8; consistent indentation per R2.7; sentence-start imperative-verb anchoring per DA2.9; allowlist-marker semantics for regex entries documented per R2.6):

    ```bash
    set -u
    # Read fixture once. Split into FIXED (substring) and REGEX (extended-regex) entries.
    FIXED_LITERALS=()
    REGEX_PATTERNS=()
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      [[ "$entry" =~ ^# ]] && continue
      if [[ "$entry" =~ ^re: ]]; then
        REGEX_PATTERNS+=("${entry#re:}")
      else
        FIXED_LITERALS+=("$entry")
      fi
    done < tests/fixtures/forbidden-literals.txt

    FAIL=0
    while IFS= read -r skill_file; do
      in_fence=0
      unset allowed_in_fence; declare -A allowed_in_fence=()
      prev_lines=()                 # contiguous marker block immediately above fence-opener
      line_no=0
      while IFS= read -r line; do
        ((line_no++))
        # BLOCKQUOTE NORMALISATION (refine-2 R2.2/DA2.2/DA2.8): strip leading
        # `>` + whitespace before applying any structural regex. Without this,
        # blockquoted fenced bash blocks like `>    ` + ` ``` ` + `bash` go
        # undetected — and the recipe blockquote at run-plan/SKILL.md:898-930
        # is the most load-bearing migration site. Empirical confirmation:
        # `[[ '   >    ```bash' =~ ^[[:space:]]*\`\`\`(bash|sh|shell)?[[:space:]]*$ ]]` → no match.
        norm_line="$line"
        if [[ "$norm_line" =~ ^[[:space:]]*\>[[:space:]]?(.*)$ ]]; then
          norm_line="${BASH_REMATCH[1]}"
        fi
        # Marker line: accumulate into prev_lines (reset prev_lines on any non-marker, non-blank line outside a fence)
        if [ "$in_fence" -eq 0 ]; then
          if [[ "$norm_line" =~ ^[[:space:]]*[\<]!--[[:space:]]+allow-hardcoded:[[:space:]]+(.+)[[:space:]]+reason:.*[-][-][\>][[:space:]]*$ ]]; then
            # Trim trailing whitespace from captured literal
            captured="${BASH_REMATCH[1]}"
            captured="${captured%"${captured##*[![:space:]]}"}"
            prev_lines+=("$captured")
          elif [[ "$norm_line" =~ ^[[:space:]]*\`\`\`(bash|sh|shell)?[[:space:]]*$ ]]; then
            # Fence-opener: marker block (if any) becomes the exemption set for this fence
            in_fence=1
            allowed_in_fence=()
            for lit in "${prev_lines[@]}"; do allowed_in_fence["$lit"]=1; done
            prev_lines=()
            continue
          else
            # Any other non-blank line resets the marker block
            [[ -n "$norm_line" ]] && prev_lines=()
          fi
          # PROSE-IMPERATIVE detection (refine-2 DA2.9 — sentence-start imperative anchoring):
          # outside any fence, flag bullet/numbered lines that contain a code-span
          # AND a sentence-start imperative verb. Lower-case `run` no longer
          # matches (was producing FPs against past-participle "has run").
          if [[ "$norm_line" =~ ^[[:space:]]*([-*]|[0-9]+\.) ]] \
             && [[ "$norm_line" =~ \`[^\`]+\` ]] \
             && [[ "$norm_line" =~ (^|[.;:][[:space:]]+|\*\*)(Run|Execute|Invoke)[[:space:]] ]]; then
            for literal in "${FIXED_LITERALS[@]}"; do
              if [[ "$norm_line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
                echo "DRIFT (prose-imperative): $skill_file:$line_no contains '$literal'."
                FAIL=1
              fi
            done
            for pattern in "${REGEX_PATTERNS[@]}"; do
              if [[ "$norm_line" =~ $pattern ]] && [ -z "${allowed_in_fence[$pattern]:-}" ]; then
                echo "DRIFT (prose-imperative): $skill_file:$line_no matches regex '$pattern'."
                FAIL=1
              fi
            done
          fi
          continue
        fi
        # Inside a fence
        if [[ "$norm_line" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
          in_fence=0
          allowed_in_fence=()
          prev_lines=()
          continue
        fi
        # Check forbidden FIXED literals (substring match)
        for literal in "${FIXED_LITERALS[@]}"; do
          if [[ "$norm_line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
            echo "DRIFT: $skill_file:$line_no contains '$literal' inside a bash fence without an allow-hardcoded marker above the fence-opener."
            FAIL=1
          fi
        done
        # Check REGEX patterns (extended regex). Allowlist key for regex entries
        # is the pattern itself WITHOUT the `re:` prefix (refine-2 R2.6) — the
        # marker `<!-- allow-hardcoded: \$TEST_OUT/\.test-results\.txt reason: ... -->`
        # exempts the regex `\$TEST_OUT/\.test-results\.txt`. Documented in
        # references/canonical-config-prelude.md.
        for pattern in "${REGEX_PATTERNS[@]}"; do
          if [[ "$norm_line" =~ $pattern ]] && [ -z "${allowed_in_fence[$pattern]:-}" ]; then
            echo "DRIFT: $skill_file:$line_no matches forbidden regex '$pattern' inside a bash fence without an allow-hardcoded marker above the fence-opener."
            FAIL=1
          fi
        done
      done < "$skill_file"
    done < <(find skills -name '*.md')
    [ "$FAIL" -eq 0 ] || exit 1
    ```

    Resolves: R2.1 (prose false-positives, original draft), refine-1 R1.4/R1.16 (line-1 boundary + outer loop), refine-1 DA1.5 (literal/regex dispatch via `re:` prefix), refine-2 R2.2/R2.7/R2.13/DA2.2/DA2.8 (blockquote-prefix stripping for both EXEC-FENCE and PROSE-IMPERATIVE; consistent indentation; regex-anchoring discipline below in fixture-format spec), refine-2 R2.6 (regex-vs-literal allowlist marker semantics), refine-2 DA2.9 (sentence-start imperative-verb anchoring eliminates "has run"/"can run" FPs).
  - **For in-fence hits**, check whether the same line OR the line immediately above contains a marker `<!-- allow-hardcoded: <literal> reason: ... -->` that names the SAME literal verbatim. (Note: bash fences don't typically contain HTML comments; the allowlist marker would be on the line above the fence start. Test handles this by extending the "line above" lookup to skip back over the fence-opener line.) Use a `[ "$line_no" -gt 1 ]` guard before checking the previous line to avoid sed errors at file-start (resolves DA2.6).
  - Failing test output: `DRIFT: skills/<file>:<line> contains '<literal>' inside a bash fence without an allow-hardcoded marker. Replace with $VAR (preferred) or add the marker if legitimately required.`
  - At the top of the test section, document the extension process: "When adding a new config field whose value could appear in skill files, add the antipattern literal to `tests/fixtures/forbidden-literals.txt`. Both the test and `hooks/warn-config-drift.sh` read from this file."

- [ ] 4.2 — **Drift-warn hook extension.** Edit `hooks/warn-config-drift.sh.template` AND `.claude/hooks/warn-config-drift.sh`. Reads the fixture file at runtime — does NOT inline the literal list (refine-1 R1.14 — earlier draft contradicted itself by inlining 3 literals while saying "read from fixture"). Structurally:

  ```bash
  # ... existing config-file matcher ...

  # New: skill-file matcher.
  # Anchored regex per refine-2 DA2.5: must match `skills/<owner>/...md`
  # (or repo-relative `^skills/...`), NOT `.claude/skills/...` (mirrors —
  # editing the source skills/ file is the canonical path; the mirror
  # gets cp-batched per feedback_claude_skills_permissions, so warning
  # twice would spam every Edit→cp pair).
  if [[ "$FILE_PATH" =~ (^|/)skills/[^/]+/.*\.md$ ]] && [[ "$FILE_PATH" != *.claude/skills/* ]]; then
    FIXTURE_PATH="$CLAUDE_PROJECT_DIR/tests/fixtures/forbidden-literals.txt"
    [ -r "$FIXTURE_PATH" ] || exit 0   # graceful no-op if fixture missing (downstream installs that bypass /update-zskills will hit this; documented limitation per refine-2 DA2.7 — see Design & Constraints below)

    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      [[ "$entry" =~ ^# ]] && continue
      if [[ "$entry" =~ ^re: ]]; then
        pattern="${entry#re:}"
        grep_args=(-nE)
        match_term="$pattern"
      else
        grep_args=(-nF)
        match_term="$entry"
      fi
      while IFS= read -r line_no_match; do
        # ... extract line number; check for allow-hardcoded marker above fence-opener ...
        # ... if no marker: emit WARN to stderr with file:line + literal ...
      done < <(grep "${grep_args[@]}" -- "$match_term" "$FILE_PATH")
    done < "$FIXTURE_PATH"
  fi
  ```

  Add the new block AFTER the existing config-matcher block to keep the two concerns separate (resolves DA1.9). Reads the literal list from `tests/fixtures/forbidden-literals.txt` — same fixture file Phase 4.1's test reads (single source of truth; resolves DA1.5 / refine-DA1.5). Dispatches `re:`-prefixed entries through `grep -E` and plain entries through `grep -F` — same dispatch as Phase 4.1. Anchored `(^|/)skills/[^/]+/.*\.md$` regex avoids: (i) mirror double-fire on `.claude/skills/...` (refine-2 DA2.5), (ii) substring FP on hypothetical paths like `dev/old_skills/x.md` (refine-2 DA2.5).

- [ ] 4.3 — **Settings.json wiring** (refine-2 DA2.6: corrected — no settings.json change needed). Earlier draft prescribed adding a new PostToolUse matcher with file-path matcher value `skills/.*\.md$`. That is invalid: Claude Code hook `matcher` selects on TOOL NAME (e.g., `"Edit"`, `"Write"`), not file path; file-path filtering happens INSIDE the hook script body. Verified at `.claude/settings.json:30-51`: existing `Edit` and `Write` matchers already wire `warn-config-drift.sh`. The Phase 4.2 skill-file branch INSIDE the script inherits this wiring automatically; no settings.json change is required. **WI 4.3 is therefore a verification step**: confirm `.claude/settings.json:30-51` has the existing Edit + Write matchers wired to `warn-config-drift.sh` and require no changes; document in the phase report.

- [ ] 4.4 — **Allowlist convention** documented in `.claude/rules/zskills/managed.md` (zskills-managed rule, ships to downstream). One-paragraph rule referencing the format spec in `references/canonical-config-prelude.md`. Two worked examples (prohibition-by-name and migration-tool literal).

- [ ] 4.5 — **Test cases for WI 4.2.** Synthetic Edit event on `skills/foo/SKILL.md` (in a temp fixture) adding a forbidden literal → assert WARN line in stderr. Synthetic Edit adding the same literal WITH the allowlist marker → assert no WARN. Tests live in `tests/test-hooks.sh`. Add a third case asserting that Edit on `.claude/skills/foo/SKILL.md` (mirror path) does NOT fire the skill-file branch (refine-2 DA2.5 mirror exclusion).

- [ ] 4.6 — **Blockquote structural AC** (refine-2 R2.2/R2.8/DA2.2/DA2.8 — load-bearing for the run-plan worktree-test recipe). New test in `tests/test-skill-conformance.sh` that extracts the blockquote bounds at `skills/run-plan/SKILL.md:898-930` (anchored on the surrounding markdown context — the lines starting with `> **Worktree test recipe:**` through the sentinel that ends the recipe) and asserts:
  - No raw literal `npm start`, `npm run test:all`, or `.test-results.txt` (without `$VAR` prefix) appears inside the bounds.
  - All three vars `$DEV_SERVER_CMD`, `$FULL_TEST_CMD`, `$TEST_OUTPUT_FILE` appear at least once each.
  - The substitution-discipline instruction at `skills/run-plan/SKILL.md:181-185` mentions all three vars by name.

  This is the structural twin of Phase 2 WI 2.2's INJECTED-BLOCKQUOTE migration, mechanized in CI. Without this AC, a future agent could revert one of the migrated `$VAR` references back to a literal and Phase 4.1's deny-list might miss it (the fence-state pseudocode now strips `>` prefix per refine-2 R2.2/DA2.8, but a structural AC adds a second line of defense and provides actionable failure messages tied to the specific load-bearing site).

- [ ] 4.7 — **Land Phase 4.1 deny-list test BEFORE Phase 2 begins** (refine-2 DA2.16 — phase ordering fix). The deny-list test (Phase 4.1 only — NOT the WARN hook in 4.2) is a CI-time gate that doesn't produce real-time spam, so it can land before Phase 2 starts. The fixture starts EMPTY (no entries; test passes trivially with zero hits). Then **Phase 2's commits add fixture entries before each batch of migration commits**: WI 2.2 adds `TZ=America/New_York` to the fixture before migrating the 60 EXEC TZ sites; adds `npm run test:all` before the 8 EXEC + 8 PROSE-IMPERATIVE sites; adds `npm start` before the 2 EXEC + 1 PROSE-IMPERATIVE sites; adds `re:\$TEST_OUT/\.test-results\.txt` before the 16 testing.output_file sites. Each migration batch is gated by the test from the moment its fixture entry lands. The WARN hook (4.2) STAYS ordered after Phase 2 is complete (it produces real-time spam during migration intermediate states; current ordering correct).

  Concrete sequencing for the implementing agent: at the start of Phase 2 work, FIRST land the empty-fixture deny-list test as a Phase-2-scoped commit (or roll it into Phase 1's helper PR). THEN proceed with WI 2.2 in batches, where each batch is "(a) append fixture entry, (b) migrate the corresponding sites, (c) commit the batch." This way each migration commit is gated by a passing deny-list test from the moment its forbidden-literal entry lands. Out-of-order migration (a batch that adds the fixture entry without migrating all sites in that category) FAILs the test before commit, surfacing the gap immediately.

### Design & Constraints

**Three layers, not one.** Test deny-list catches at CI time (strong gate, blocks merge). Drift-warn hook catches at edit time (real-time nudge, non-blocking). Allowlist comments are inspectable in raw markdown next to the literal (low ceremony for legitimate exemptions). Combined: incident on commit + nudge during editing + low-friction exemption mechanism.

**Forbidden-literal list maintenance.** Single source of truth in `tests/fixtures/forbidden-literals.txt` (refine round 1 fix). Both the test (Phase 4.1) and the drift-warn hook (Phase 4.2) read this file at runtime. Config-derived auto-list rejected: per-downstream config means different literals would be deny-listed in different downstreams, breaking shared skill-file consistency. Post-refine-1 list contents (4 entries — `scripts/port.sh` removed since migration is done; `.test-results.txt` reformulated as anchored regex to avoid colliding with the migration's `${TEST_OUTPUT_FILE:-.test-results.txt}` fallback default):

```
# tests/fixtures/forbidden-literals.txt
TZ=America/New_York                  # use ${TIMEZONE:-UTC}
npm run test:all                     # use $FULL_TEST_CMD
npm start                            # use $DEV_SERVER_CMD
re:\$TEST_OUT/\.test-results\.txt    # use $TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}
```

**Allowlist scope.** The marker exempts ONE literal on the same line OR the line immediately above. Reviewer can inspect markers in PR diff. Misuse is visible.

**Hook-skill collision concern** (per `feedback_prefer_inspectable_skill_output_over_permissive_hook_heuristics`). The drift-warn hook is non-blocking (WARN only); cannot block legitimate edits. The test deny-list IS blocking but is inspectable — exemption requires a literal allowlist comment, not a heuristic bypass.

**Downstream coverage scope** (refine-2 DA2.7 — bounded honesty). The drift-warn hook's skill-file branch (WI 4.2) reads from `tests/fixtures/forbidden-literals.txt`. `tests/` is NOT installed downstream by `/update-zskills` — only `skills/`, `hooks/`, `.claude/rules/zskills/managed.md`, and skill-machinery scripts under `.claude/skills/<owner>/scripts/` ship. Consequence: the hook's skill-file branch silently no-ops in any downstream project that bypasses zskills's own CI. **The hook is therefore zskills-CI-only** for the skill-file branch, despite the Overview's "drift surface is N projects wide" framing. This is acceptable — the hook's job is to nudge agents WHEN editing skills, and the only agents editing zskills's `skills/*.md` files are agents working in the zskills repo itself (downstream projects consume mirrored `.claude/skills/*.md` but don't typically edit them; if they do, the warn-config-drift.sh's existing config-file branch already covers `.claude/zskills-config.json` edits, which is the load-bearing surface for downstream behavior). Document this limitation as: "WI 4.2's skill-file branch fires in the zskills repo; downstream projects rely on the deny-list test (4.1) running in zskills CI before skills are mirrored to them. Downstream agents editing their installed `.claude/skills/*.md` mirrors will not receive the WARN; this is intentional — those are downstream-local edits, not upstream skill drift." Drop "drift surface is N projects wide" framing from the WI 4.2 rationale (the deny-list test 4.1 IS the N-projects-wide protection — it gates what zskills CI ships to N downstreams).

**Downstream-shipping option (deferred unless evidence)**: shipping `forbidden-literals.txt` to downstream as `.claude/skills/update-zskills/references/forbidden-literals.txt` (and updating WI 4.2 to read from that path with the existing graceful-no-op guard) would activate the hook downstream. Deferred because: (a) the deny-list test running in zskills CI already protects shipped skills before they reach downstream; (b) downstream-local edits to mirrored skills are not the load-bearing drift surface; (c) shipping the fixture creates a new install-integrity surface (out-of-sync fixture between zskills and downstream after a fixture update). If a real downstream-edit drift incident materializes, file a follow-up to ship the fixture.

### Acceptance Criteria

- [ ] `bash tests/run-all.sh` includes the new deny-list section asserting zero unmarked-hardcode regressions.
- [ ] Drift-warn hook test cases pass (synthetic Edit with/without allowlist marker).
- [ ] `.claude/settings.json` shows the new PostToolUse matcher.
- [ ] `.claude/rules/zskills/managed.md` documents the allowlist convention with at least 2 worked examples.
- [ ] Manual smoke test: in a live session, edit a skill file to add `TZ=America/New_York` literal; observe the WARN in session stderr.
- [ ] **Fixture-extension coverage test (refine-1 R1.17).** Append a synthetic literal `__TEST_LITERAL__` to a temp copy of `tests/fixtures/forbidden-literals.txt`; create a synthetic skill file containing `__TEST_LITERAL__` inside a bash fence; run BOTH the deny-list test (Phase 4.1) and the drift-warn hook (Phase 4.2) against it; assert both emit the expected DRIFT/WARN line. Restore the fixture at end. This proves the single-source-of-truth claim — adding to the fixture immediately enforces in both surfaces with no code change.

### Dependencies

Phase 1 (allowlist marker format spec must exist in canonical-prelude doc).

**Split ordering** (refine-2 DA2.16 fix — earlier draft said "Phase 4 lands AFTER Phase 2 fully complete," but that left Phase 2's commits ungated by the deny-list):

- **WI 4.1 (deny-list test) + WI 4.7 (early-land mechanism) land BEFORE Phase 2 begins** with an empty fixture. Each Phase-2 migration batch appends the corresponding fixture entry as part of the batch commit, which gates the batch against the test (out-of-order migration fails CI before commit).
- **WI 4.2 (drift-warn hook) lands AFTER Phase 2 is fully complete.** Installing the WARN hook before Phase 2 is done would produce WARN spam during the migrating agent's intermediate states (one fence migrated, another not yet). The WARN hook is real-time edit-time noise, not CI; spam is intolerable.
- **WI 4.3 (settings.json verification), WI 4.4 (rule paragraph), WI 4.5 (hook tests), WI 4.6 (blockquote structural AC)** land AFTER Phase 2. WI 4.6 specifically depends on Phase 2's INJECTED-BLOCKQUOTE migration being complete (the AC asserts the structural invariant that Phase 2 WI 2.2 establishes).

Resolves DA2.8 (original concern: WARN spam) AND DA2.16 (new concern: Phase 2 commits ungated).

## Phase 5 — Verification + Drift-Regression Test

### Goal

End-to-end verification + cross-reference DRIFT_ARCH_FIX with the gap closure.

### Work Items

- [ ] 5.1 — Run `/verify-changes branch` on the feature branch. All 4 prior phases' commits inspected for diff correctness, scope assessment, mirror parity. Resolve any flags.

- [ ] 5.2 — **Two-sided drift-regression test** in `tests/test-skill-conformance.sh`:
  - **Negative side** (already in Phase 4.1): no unmarked forbidden literals.
  - **Positive side** (NEW in 5.2; refine-2 DA2.14/DA2.17 hardening — fence-local, not file-global). The earlier draft's positive-side check was file-global: any skill `.md` file containing a `$VAR` reference (matching `\$\{?(UNIT_TEST_CMD|FULL_TEST_CMD|TIMEZONE|DEV_SERVER_CMD|TEST_OUTPUT_FILE|COMMIT_CO_AUTHOR)\}?`) was required to also contain `zskills-resolve-config.sh` somewhere in the file. That misses the regression mode where one fence among many in `run-plan/SKILL.md` adds a new `$VAR` reference without the preamble — the file-global check still passes because OTHER fences in the file already source the helper.

    **Fence-local check** (refine-2 DA2.14). For each bash fence in each skill `.md` file, if the fence body contains any of the 6 vars in `${VAR:-default}` or `$VAR` form (bare or braced), the fence body OR the immediately-preceding line MUST contain `zskills-resolve-config.sh` (the helper preamble). Detection uses the same fence-state pseudocode as Phase 4.1, with an additional in-fence accumulator that resets at each fence-open and checks at each fence-close. PROSE references to vars outside fences (e.g., `skills/run-plan/SKILL.md:181-185`'s discipline annotation, `:1208-1210`'s "the orchestrator substitutes `$FULL_TEST_CMD`") are NOT consumers — they're explanation — and the fence-local check correctly ignores them (refine-2 DA2.17 false-positive elimination).

    Pseudocode skeleton (the implementing agent fleshes out — same loop structure as Phase 4.1 with the addition of a `fence_uses_var` and `fence_has_preamble` accumulator pair, with comparison at fence-close):

    ```bash
    # Per-fence accumulators reset on fence-open
    fence_uses_var=0
    fence_has_preamble=0
    # ... when in_fence=1 and line matches \$\{?(VAR_LIST)\}? → fence_uses_var=1
    # ... when in_fence=1 and line contains 'zskills-resolve-config.sh' → fence_has_preamble=1
    # ... when in_fence transitions 1→0 (fence-close):
    #     if fence_uses_var && !fence_has_preamble: emit DRIFT (positive-side)
    ```

    Dynamic detection avoids maintaining a hardcoded list (resolves Round-3 finding 3.9). Together with the negative side, this catches both regression modes: literal restored (negative side fails) or helper-source removed leaving dangling `$VAR` (positive side fails — fence-locally, so subtle one-fence regressions in a mostly-migrated file are caught).

- [ ] 5.3 — **Cross-reference DRIFT_ARCH_FIX.** Append to `plans/DRIFT_ARCH_FIX.md` (after its "Plan Quality" section) a one-line "see also" pointer: *"This plan migrated CODE consumers and TEXT consumers but did not address skill `.md` files containing bash fences. That gap is closed by `plans/SKILL_FILE_DRIFT_FIX.md`."* Resolves the user's frustration about banner-overstating without rewriting the original plan's history.

- [ ] 5.4 — Update `plans/PLAN_INDEX.md` to mark this plan as Active during execution and Complete after landing. Add the new file to the index per the existing convention.

- [ ] 5.5 — Add a one-paragraph rule to `.claude/rules/zskills/managed.md` (or extend Phase 4.4's allowlist-convention paragraph): *"Skill `.md` files MUST resolve config-derived values via the canonical block in `references/canonical-config-prelude.md`. Hardcoded literals trigger the deny-list test (`tests/test-skill-conformance.sh`) and the drift-warn hook (`hooks/warn-config-drift.sh`). Exemptions require an inspectable `<!-- allow-hardcoded: ... -->` marker per the format spec."*

- [ ] 5.6 — **Live blockquote-emission smoke** (refine-2 R2.8 follow-on). Since the blockquote-substitution discipline is model-side (not bash-mechanical), the structural AC at WI 4.6 + the deny-list at 4.1 catch the markdown-source surface, but they cannot verify that the orchestrator-model actually substitutes `$DEV_SERVER_CMD`/`$TEST_OUTPUT_FILE` literals before emission to a dispatched subagent. Run a manual smoke against a live `/run-plan` dispatch in a fixture project with `dev_server.cmd: "yarn start"` and `testing.output_file: ".out.log"` configured. Inspect the dispatched subagent's prompt (via the standard subagent-prompt-capture pattern in `tests/run-all.sh` if available, or via /run-plan's tracking markers / report); assert it contains literal `yarn start &` and `$TEST_OUT/.out.log`, NOT `$DEV_SERVER_CMD &` or `$TEST_OUT/$TEST_OUTPUT_FILE` (literal-unresolved means the model failed the discipline). If the standard tracking markers don't expose dispatch-prompt content, document the smoke as a manual verification step in the phase report rather than an automated test — the model-side discipline is empirically observable but not mechanically testable from outside the orchestrator session.

- [ ] 5.7 — **PROSE-IMPERATIVE substitution-discipline coverage** (refine-2 R2.12 follow-on). For each of the 9 PROSE-IMPERATIVE-migrated sites (8 `npm run test:all` + 1 `npm start`), assert that within 5 lines of the migrated `$VAR` reference (forward or backward in the same skill file), there is EITHER (a) an inline resolution-discipline annotation referencing `zskills-resolve-config.sh` OR (b) a pointer to a per-skill canonical-prelude config-read block (existing `CONFIG_CONTENT=$(cat ...)` pattern). Implementing agent codifies the test as a per-site grep loop in `tests/test-skill-conformance.sh`. Failure: `FAIL: PROSE-IMPERATIVE site at <file>:<line> uses $<VAR> without nearby resolution-discipline annotation. Add an inline `(resolve via ...)` or pointer to the skill's config-read block.`

### Design & Constraints

**No new architecture in Phase 5.** Verification + documentation only. If `/verify-changes` surfaces a real architectural issue, file as follow-up.

**Two-sided regression test.** Negative side catches obvious regressions (re-hardcoded literal). Positive side catches subtle regressions (canonical block removed, leaving `$VAR` references that resolve to empty — silent breakage).

### Acceptance Criteria

- [ ] `/verify-changes branch` reports clean.
- [ ] `bash tests/run-all.sh` passes; new two-sided drift-regression test passes.
- [ ] `plans/PLAN_INDEX.md` reflects the new plan; `plans/DRIFT_ARCH_FIX.md` has the cross-reference appended.
- [ ] `.claude/rules/zskills/managed.md` has the new rule paragraph.

### Dependencies

Phases 1-4.

## Out of Scope

- **`commit.co_author` field altogether removing from config schema**: out of scope — keeping the field, just removing the version-specific hardcoded default. If a downstream wants strict no-default behavior, they can set the field explicitly.

- **Auto-deriving the deny-list from `.claude/zskills-config.json` values**: rejected for cross-downstream consistency. Different downstreams have different config values, so an auto-list would deny different literals in different downstreams, breaking shared skill-file consistency. Hardcoded list with documented extension process is simpler.

### Audit also surveyed (verified legitimate, not candidates for migration)

The audit ran wide-net greps for related strings (`pr`/`cherry-pick`/`direct` enum values, `npm run test:all` and `TZ=America/New_York` in documentation contexts, prohibition-by-name lines, migration-tool literal references, examples in plan-quality reports). Total: roughly 2200+ string appearances in skill files. **All verified as legitimate uses** — pattern matching against config values (`if [[ "$LANDING_MODE" == "pr" ]]`), correct documentation, intentional prohibitions like `skills/run-plan/SKILL.md:179` ("Never hardcode `npm run test:all`"), migration-tool literal references in `skills/update-zskills/SKILL.md` that detect the antipattern by name. **Not candidates for migration. Listed here only to document audit coverage; not deferred work.**

<!-- Earlier draft framed these as "out of scope categories with counts (~1583 / ~670)" which misleadingly implied 2200+ deferred candidates. Refine round 3 reframed: these are background grep noise, not candidates. The 85 actual drift bugs are enumerated by file:line in Phase 2. -->

<!-- co_author was deferred here in earlier rounds. Refine round 3 (anti-deferral pass) initially brought it into scope with a version-independent string default in skills, but follow-up review (user-driven) noted that "Claude Code" loses AI-attribution intent. Final design: schema-default carries the version-specific identity ("Claude Opus 4.7 (1M context) <noreply@anthropic.com>"); skills drop the hardcoded default entirely and source $COMMIT_CO_AUTHOR from helper; trailer emits conditionally (skip if empty — supports consumer opt-out). When Anthropic releases new Claude versions, schema bump propagates via /update-zskills --rerender. Single source of truth for the version string. -->

<!-- Refine round 3 audit: removed the "PROSE-IMPERATIVE deferred" entry (brought into Phase 2 WI 2.5); removed the "Move canonical block to sourced location: deferred" entry (already adopted via Phase 1 helper script in refine round 1). -->
<!-- Note: Option B (sourced helper script) was originally listed as out-of-scope in the round-1 draft but was adopted in round 2 after DA2.2 (inlined-block divergence) was identified as a blocker. The helper now lives at `skills/update-zskills/scripts/zskills-resolve-config.sh` per Phase 0's coordination with SCRIPTS_INTO_SKILLS_PLAN. -->

### Items REMOVED from Out of Scope in refine round 3 (anti-deferral pass)

- **PROSE-IMPERATIVE migration (8 sites)** — was deferred with "model doesn't execute these as bash"; that claim was wrong. Brought into Phase 2 WI 2.2 (per-fence migration handles same-file prose) and Phase 4.1 (deny-list extends to detect literal-as-imperative outside fences).
- **`testing.output_file` (.test-results.txt) hardcodes (10 sites)** — original audit missed this category; brought into Phase 1 (helper resolves `TEST_OUTPUT_FILE`) and Phase 2 (migration).
- **`commit.co_author` hardcoded default (2 sites + schema)** — was deferred with "substantively different drift class"; rationale was thin. Brought into Phase 2: skills drop their hardcoded `CO_AUTHOR=...` lines entirely and source `$COMMIT_CO_AUTHOR` from helper; the version-specific identity moves to the schema default for `commit.co_author`; /update-zskills backfills missing fields; skills emit Co-Authored-By trailer conditionally (skip if empty for consumer opt-out).
- **`scripts/port.sh` skill-fence references (5 sites)** — original audit missed this category; brought into Phase 2 in refine round 3, **then closed before this plan's execution** (refine-1 R1.3 / DA1.1) because SCRIPTS_INTO_SKILLS_PLAN PRs #94-#100 already migrated all 5 sites to the post-runtime path. Verified `grep -rE 'bash scripts/port\.sh|\(scripts/port\.sh\)' skills/` → 0 hits. Scope reduced 7 → 6 categories.
- **Hook fallback sweep beyond `block-unsafe-project.sh:311`** — Phase 3 WI extended to grep for ALL `${VAR:-default}` patterns in `hooks/*.template` and `.claude/hooks/*.sh`, not just the one known instance.

## Risks & Mitigations

- **Risk**: Phase 2's ~96-site mechanical migration touches 27 files (refine-1 R1.2 / R1.11); review fatigue. **Mitigation**: 1-line preamble + per-literal substitution per fence keeps diffs compact (~195 lines added across migration vs ~1000 with the rejected inline-block design); Phase 5.1 `/verify-changes branch` is independent fresh-eyes review.
- **Risk**: zskills's own config matches the hardcoded values, so migration appears functional in zskills CI even if broken for other downstreams. **Mitigation**: Phase 1's helper-script fixture test uses synthetic `Europe/London`; Phase 2.5 end-to-end fixture test exercises a migrated fence with non-default timezone; deny-list catches literal regardless of resolution.
- **Risk**: Helper script not present in downstream after `/update-zskills`. **Mitigation**: Phase 0's staleness gate ensures SCRIPTS_INTO_SKILLS_PLAN has landed first, so the skill-mirror install pathway (which delivers `update-zskills` skill content) is already exercising before this plan's helper is added. Phase 1's install-integrity test runs `/update-zskills` against a fixture and asserts the helper is rendered at `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh`.
- **Risk**: Quoted heredocs (`<<'TAG'`) need pre-substitution. **Mitigation**: Phase 2.1 enumerates ALL heredocs by form before migrating; spot-check round 2 found none in the migration set (3 quoted heredocs total in repo, all for commit-message bodies).

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (reviewer + devil's advocate, dispatched in parallel each round).

**Convergence:** Converged at round 3. Rounds 1 and 2 each surfaced an architectural blocker that drove a substantial reframe; round 3 surfaced only specification errors which were corrected without reframing.

### Round History

| Round | Reviewer | DA | Total | Resolved | Outcome |
|-------|----------|----|-------|----------|---------|
| 1 | 11 (3 blocker + 6 major + 2 minor) | 11 (2 blocker + 4 critical + 5 major) | 16 distinct (post-dedup) | 15 fixed + 1 justified | **Architectural reframe**: rejected "preflight propagates `$VAR`" assumption (verified empirically that bash shell state does not persist across Bash tool calls); adopted "inline canonical block per fence" matching existing `run-plan/modes/pr.md:325-345` pattern |
| 2 | 5 (1 critical + 1 major + 2 minor + 1 nit) | 13 (1 blocker + 3 critical + 7 major + 1 minor) | 18 distinct (post-dedup) | 15 fixed + 3 justified | **Second architectural reframe**: rejected "inline canonical block per fence" (30-40 fences × 25 lines ≈ 1000 lines duplicated would drift); adopted **sourced helper script** (`scripts/zskills-resolve-config.sh`) with one-line preamble per fence — `scripts/` already ships 10+ helpers via `/update-zskills`, so install-dependency concern was overstated |
| 3 | (combined reviewer+DA) | 9 (2 critical + 4 major + 3 minor) | 9 | 7 fixed + 2 justified | **Specification corrections only**: critical findings were narrow (`.claude/scripts/` shouldn't exist; preamble must use `--show-toplevel` for worktree-correctness), not architectural; design holds |

### Remaining concerns

None blocking. Two acknowledged limitations:

- **Helper-script reliance on `/update-zskills` install integrity** — Phase 1 AC includes an install-integrity test against a fixture, but downstream projects that bypass `/update-zskills` and copy skills manually will lack the helper. Documented; failure mode is explicit (empty vars + critical-path empty-checks → fail-closed with `/update-zskills` pointer).

- **Bash-shell assumption** — the helper uses bash regex (`BASH_REMATCH`). If a future skill consumer runs under `dash`/`sh`, this breaks. Current convention is bash for all skill fences (per existing patterns). Documented but not enforced.

### Post-finalize revision (2026-04-25)

After finalize, the user identified an architectural conflict with two in-flight plans (`SCRIPTS_INTO_SKILLS_PLAN.md`, `CONSUMER_STUB_CALLOUTS_PLAN.md`) that I had not accounted for. The original draft placed the helper at top-level `scripts/`, but SCRIPTS_INTO_SKILLS_PLAN explicitly moves skill-machinery scripts OUT of `scripts/` into `skills/<owner>/scripts/`. The new helper is clearly Tier-1 skill machinery, so:

- **Phase 0 staleness gate added** (mirrors CONSUMER_STUB_CALLOUTS_PLAN's pattern): halt if SCRIPTS_INTO_SKILLS_PLAN hasn't landed.
- **Helper relocated** to `skills/update-zskills/scripts/zskills-resolve-config.sh` (`update-zskills` is the natural owner since config-resolution is its domain).
- **Sourcing path updated** throughout: `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`.
- No architectural reframe — the helper-script design from round 2 still holds. Only location/dependency change.

## Drift Log

Plan was authored in working tree on 2026-04-25 via `/draft-plan` (3 rounds adversarial review). No prior version exists in git history (untracked at /refine-plan time). Drift Log based on internal evidence only:

| Phase | Original spec (post-/draft-plan round 3) | Current spec (post-/refine-plan round 2) | Delta |
|-------|------------------------------------------|------------------------------------------|-------|
| 0 | (didn't exist) | Staleness gate, 5 work items, 4 anchor pairs + CHANGELOG + export checks | NEW phase added in post-finalize revision (2026-04-25); strengthened in /refine-plan round 1; Phase 0 grep made whitespace-tolerant (refine-1 R1.18); ZSKILLS_MONITOR/CONSUMER_STUB_CALLOUTS gates explicitly NOT added (refine-1 R1.19) |
| 1 | Helper at top-level `scripts/`, 1-line preamble using `git rev-parse --show-toplevel` | Helper at `skills/update-zskills/scripts/`, 1-line preamble using `$CLAUDE_PROJECT_DIR` | Location relocated (post-finalize); sourcing convention aligned with SCRIPTS_INTO_SKILLS_PLAN (refine round 1); WI 1.2 reframed verification-only since schema + backfill already exist (refine-1 R1.7); helper coexistence with `zskills-stub-lib.sh` documented disjoint (refine-1 R1.9); baseline test count 826→1212 (refine-1 R1.12) |
| 2 | 3 work items (timezone migration, test-cmd migration, dev-server migration as separate WIs) | 5 work items, consolidated by-fence with empty-check guards; fence-state pseudocode for AC verification | Migration discipline tightened in /draft-plan round 1-3; refine-1 dropped `scripts/port.sh` migration sub-bullet (already landed via SCRIPTS_INTO_SKILLS_PLAN — R1.3); added INJECTED-BLOCKQUOTE sub-bullet for `run-plan/SKILL.md:898-930` with `__SNAKE__` template-substitution markers + sed pre-emission (R1.5); enumerated work-on-plans + zskills-dashboard EXEC TZ sites (R1.8); inline config-read blocks marked OUT-OF-SCOPE with follow-up (R1.10); `.test-baseline.txt` marked OUT-OF-SCOPE (R1.6); cite-derivation deferred to execution time (R1.4); line-budget revised ~130 → ~195 (R1.11); mirror-parity AC switched to `find` (R1.20) |
| 3 | Three-case tree replacement at line 311 + sync test | Same scope; sync mechanism extracted to `tests/fixtures/test-infra-patterns.txt` shared file | /draft-plan round 2: explicit shared-fixture file pattern |
| 4 | Test deny-list + drift-warn extension + allowlist comments; FORBIDDEN_LITERALS list defined twice | Same scope; `tests/fixtures/forbidden-literals.txt` shared file; pseudocode rewritten with character-class `[<]` and `[>]` regex (refine round 2 fix for bash quoting) | /refine-plan round 1-2: shared-fixture file + regex robustness; refine-1 dropped `scripts/port.sh` from fixture (R1.13); `.test-results.txt` reformulated as anchored regex `re:\$TEST_OUT/\.test-results\.txt` to avoid migration-fallback substring collision (DA1.5); fixture format gained `re:` prefix dispatch; pseudocode added outer skill_file loop + line_no=0 init (R1.16); hook reads fixture not inlined literals (R1.14); fixture-extension coverage AC added (R1.17) |
| 5 | Two-sided drift-regression test, positive-side regex `\$(VAR)` | Same scope; positive-side regex expanded to `\$\{?(VAR)\}?` to match braced forms | /refine-plan round 1: regex covers `${TIMEZONE:-UTC}` migration output; refine-1 extended regex to all 6 helper-resolved vars (R1.15) |

## Plan Review

**Drafting + refinement process:** `/draft-plan` 3 rounds (2026-04-25) → user-driven post-finalize revision (Phase 0 + relocation, 2026-04-25) → `/refine-plan` 2 rounds (2026-04-26) → `/refine-plan` re-run rounds 1+2 (refine-4 + refine-2 in the table below; 2026-04-29) re-grounding against current main `e3acd40`+`4aa8864` and pressure-testing refine-1's three new mechanisms (`__SNAKE__` + sed, `re:` prefix, helper coexistence).

**Convergence:** Converged at refine-2 (= /refine-plan re-run round 2). The blockquote/`__SNAKE__` cluster (refine-2 R2.1/R2.2/R2.8/DA2.1/DA2.2/DA2.3/DA2.8) was the load-bearing concern — refine-1 shipped a sed-based mechanism without a host fence and without Phase 4 enforcement coverage. Refine-2 dropped the mechanism in favor of the existing model-side `$VAR` discipline (already working for `$FULL_TEST_CMD`), strengthened the discipline instruction, made Phase 4 enforcement blockquote-aware, and added a structural AC. All 36 round-2 findings dispositioned — no blocker residuals.

**Remaining concerns:** None blocking. Cite-drift will continue to accumulate in highly-edited files (commit/SKILL.md, fix-issues/SKILL.md, run-plan/SKILL.md); the plan now defers cite-derivation to execution-time greps rather than baking line numbers in. Live blockquote-emission (model-side substitution) is verifiable only via WI 5.6 manual smoke; this is acceptable — model-discipline is empirically observable but not mechanically testable from outside the orchestrator session.

### Round History

| Round | Reviewer | DA | Substantive | Resolved | Outcome |
|-------|----------|----|-------------|----------|---------|
| draft-1 | 11 (3 blocker + 6 major + 2 minor) | 11 (2 blocker + 4 critical + 5 major) | 16 (post-dedup) | 15 fixed + 1 justified | Architectural reframe: rejected "preflight propagates `$VAR`" assumption |
| draft-2 | 5 | 13 | 18 (post-dedup) | 15 fixed + 3 justified | Architectural reframe: adopted sourced helper script (rejected inline-block design) |
| draft-3 | (combined) | (combined) | 9 | 7 fixed + 2 justified | Specification corrections (`.claude/scripts/` ref, `--show-toplevel` worktree-correctness) |
| refine-1 | 8 | 6 | 7 | 7 fixed | Sourcing path → `$CLAUDE_PROJECT_DIR` (convention alignment); Phase 0 strengthened; positive-side regex expanded; FORBIDDEN_LITERALS shared file; fence-state pseudocode rewritten; baseline test count 815→826 |
| refine-2 | (combined) | (combined) | 2 | 2 fixed | Pseudocode bugs surfaced from refine-1 fix: `\<` non-portable across bash regex contexts → character class `[<]`; multi-token literal capture via ` reason:` delimiter |
| refine-3 | 8 (2 critical + 2 major + 2 minor + 2 nit) | 9 (2 critical + 4 major + 3 minor) | 13 (post-dedup) | 12 fixed + 1 not-reproduced (DA3.6 regex; verified empirically) | **Anti-deferral pass.** User-driven: caught the plan deferring PROSE-IMPERATIVE migration ("model doesn't execute these as bash" was wrong) and missing two config-field categories the original audit never swept. Brought into scope: 8 PROSE-IMPERATIVE sites (`npm run test:all` instructions, exact list per re-grep + manual classification); 10 `.test-results.txt` hardcodes (testing.output_file); 5 `scripts/port.sh` references (will break post-SCRIPTS_INTO_SKILLS_PLAN); 2 `co_author` default-overrides (Claude-version drift). Helper extended to resolve TEST_OUTPUT_FILE; fixture file expanded to 5 entries; Phase 4 deny-list extended to detect PROSE-IMPERATIVE outside fences (bullet + code-span + imperative-verb heuristic); Phase 3 sweeps ALL hook fallbacks not just the one known instance. Stale prose at lines 313, 422, 484 fixed. **Total scope grew from 60 → 85 hardcoded references across 7 categories.** Verified clean: `dev_server.main_repo_path`, `ui.auth_bypass`, `agents.min_model` (0 hits each in skill bash fences). |
| refine-4 (= /refine-plan re-run round 1, post-active drift re-grounding) | 20 (5 critical + 7 major + 6 minor + 2 nit) | 15 (in combined R+DA review) | 35 reviewer findings (post-dedup; many overlap) | 17 fixed + 18 justified-as-overlap | **Re-grounding against current main (`e3acd40`).** All cited counts verified by re-grep. Net findings: (a) `scripts/port.sh` 5-site migration is a no-op — already landed by SCRIPTS_INTO_SKILLS_PLAN PRs #94-#100. Scope 7→6 categories, total 85→~96 in raw counts. (b) Two NEW skills (`/work-on-plans`, `/zskills-dashboard`) added 6 EXEC TZ sites enumerated post-audit. (c) Verbatim-injected blockquote at `skills/run-plan/SKILL.md:898-930` carries hardcodes into every dispatched subagent prompt — markdown-text emission doesn't expand `${VAR:-default}` so per-literal substitution rule fails for this site. Resolution: orchestrator-resolved `__SNAKE__` template-substitution markers + sed pre-emission. (d) Schema + backfill for `commit.co_author` already exist in `config/zskills-config.schema.json:55` and `skills/update-zskills/SKILL.md:226-234`; WI 1.2 reframed as verification-only. (e) Most cited file:line numbers drifted +20 to +110 lines across highly-edited files (commit/SKILL.md, fix-issues/SKILL.md, run-plan/SKILL.md); plan now defers cite-derivation to execution time with refine-1 cites as snapshots. (f) `.test-results.txt` deny-list entry would substring-match the migration's own `${TEST_OUTPUT_FILE:-.test-results.txt}` fallback default; reformulated as anchored regex `re:\$TEST_OUT/\.test-results\.txt`. (g) `.test-baseline.txt` (sibling filename) explicitly OUT-OF-SCOPE with rationale. (h) Phase 4.1 pseudocode gained outer skill_file loop + `line_no=0` init; Phase 4.2 hook reads fixture instead of inlining 3 literals. (i) Positive-side regex extended to all 6 helper-resolved vars. (j) Mirror-parity AC switched from globstar to find. (k) Inline config-read blocks (6 sites) explicitly OUT-OF-SCOPE with follow-up note. (l) Baseline test count 826 → 1212 (re-derived). (m) Helper coexistence with `zskills-stub-lib.sh` documented as domain-disjoint. **No architectural reframe; all changes are corrections, scope adjustments, or substantive design gaps closed in place.** |
| refine-2 (round 2 of /refine-plan; pressure-tests refine-1's mechanisms) | 14 (3 critical + 4 major + 5 minor + 1 nit + 1 justified-no-fix) | 22 (2 blocker + 2 critical + 11 major + 5 minor + 1 nit + 1 verification-finding) | 36 reviewer findings (substantial overlap on the blockquote/`__SNAKE__` cluster) | 33 fixed + 3 justified | **Architectural reframe of refine-1's R1.5 INJECTED-BLOCKQUOTE fix.** The `__SNAKE__`-marker + `sed` pre-emission mechanism specified a host fence that does not exist (verified: `grep -rn 'RAW_RECIPE\|RECIPE_TEXT\|__DEV_SERVER_CMD__\|__TEST_OUTPUT_FILE__' skills/` → 0 hits) and would break on `\|` characters in config values (verified empirically). The Phase 4 deny-list pseudocode AND PROSE-IMPERATIVE detection both miss blockquote-prefixed (`>` ) fenced bash blocks and bullet lines (verified: `[[ '   >    \`\`\`bash' =~ ^[[:space:]]*\`\`\`(bash\|sh\|shell)?[[:space:]]*$ ]]` → no match). **Resolution:** drop the `__SNAKE__`/sed mechanism entirely; migrate the blockquote literals to `$VAR` references and rely on the existing model-side substitution discipline at `skills/run-plan/SKILL.md:181` (which already works for `$FULL_TEST_CMD`); strengthen that discipline instruction to enumerate all three vars (`$FULL_TEST_CMD`, `$DEV_SERVER_CMD`, `$TEST_OUTPUT_FILE`); update Phase 4.1 pseudocode to strip `>` prefix before applying fence-opener / bullet / imperative regexes; add Phase 4 WI 4.6 structural AC asserting blockquote contains only `$VAR` references; split Phase 4 ordering — WI 4.1 deny-list lands BEFORE Phase 2 (with empty fixture, populated in batches per migration commit), WARN hook stays after. **Other notable fixes:** WI 4.3 corrected (settings.json matcher is tool-name not file-path; existing Edit+Write wiring suffices — refine-2 DA2.6); hook regex anchored to exclude `.claude/skills/` mirrors (DA2.5); PROSE-IMPERATIVE imperative-verb anchored at sentence-start (DA2.9 eliminates "has run" FPs); regex-vs-literal allowlist marker semantics documented (R2.6); `re:` prefix collision/escape limitation documented (R2.5/DA2.22); regex anchoring discipline documented (R2.13); pseudocode indentation fixed (R2.7); `.test-baseline.txt` OOS rationale corrected — hook embeds `.test-results.txt` in message text not detection (R2.10); Phase 3 WI 3.1 extended to fix `.test-results.txt` literal in the hook's suggestion-message text (DA2.13); `--show-toplevel` leftover refs purged (DA2.4); schema path `config/...` consistent across phases (R2.3); 96-vs-97 math reconciled to 97 with INJECTED-BLOCKQUOTE-not-double-counted note (R2.4); investigate:210 read added to TEST_OUT enumeration (DA2.11); verify-changes:687 npm-start PROSE-IMPERATIVE site enumerated (DA2.10); Phase 5.2 positive-side switched from file-global to fence-local (DA2.14, DA2.17); Phase 2 AC categorical re-audit mechanized via deny-list test (DA2.15); Phase 2 WI 2.5 fixture test mechanism specified (DA2.20); Phase 1 AC worktree test simplified to CLAUDE_PROJECT_DIR-switching (DA2.19); helper-coexistence forward-looking shared-infrastructure note added (R2.11); WI 5.6 live blockquote-emission smoke + WI 5.7 PROSE-IMPERATIVE substitution-discipline coverage added; round-1 disposition bookkeeping corrected (R2.9 — 17 Fixed → 28 Fixed rows, 3 Justified → 7 Justified rows); helper-downstream-coverage scope honesty documented (DA2.7). |

**Total findings across all rounds: 136 (65 draft + 35 refine-1 + 36 refine-2). Resolved: 119 fixed, 17 justified. Zero deferred or ignored.**

### Notable catches

- **Empirical verification** (draft-1) prevented shipping a fundamentally broken architecture (bash shell state non-persistence).
- **Inlined-block divergence blocker** (draft-2) prevented shipping ~1000 lines of duplicated boilerplate.
- **Worktree-config bug** (draft-3) caught `--git-common-dir` vs `--show-toplevel` distinction.
- **Sourcing-path convention violation** (refine-1) caught inconsistency with SCRIPTS_INTO_SKILLS_PLAN's `$CLAUDE_PROJECT_DIR` rule (lines 175-195) — `--show-toplevel` would have worked in practice but violated the locked convention; future divergence risk.
- **Bash regex quoting quirk** (refine-2) — `\<` works in inline regex but fails in `$var` regex; character class `[<]` is portable across both contexts. Verified empirically with `[[ '<!-- foo' =~ ... ]]` in both forms.
- **Round-1 fix introduced its own architectural blocker** (refine-2 R2.1/R2.2/R2.8/DA2.1/DA2.2/DA2.8/DA2.21) — R1.5's `__SNAKE__` + sed mechanism specified a host fence (`$RAW_RECIPE_TEXT`) that did not exist anywhere in the codebase, and the Phase 4 deny-list it was supposed to be gated by could not detect blockquote-prefixed fences. Caught in refine-2 because the round-2 directive explicitly pressure-tested the round-1 fix; without that discipline the plan would have shipped a non-implementable substitution mechanism. Lesson: every fix that introduces a new mechanism MUST be re-pressure-tested in the next round against the host code it claims to live in. Verified: `grep -rn 'RAW_RECIPE\|RECIPE_TEXT' skills/` → 0 hits.
- **Hook matcher schema misdescription caught** (refine-2 DA2.6) — earlier WI 4.3 prescribed adding a settings.json matcher with file-path value `skills/.*\.md$`, but Claude Code matchers select on TOOL NAME not file path. File-path filtering happens inside the script body. Verified at `.claude/settings.json:30-51` and confirmed `warn-config-drift.sh` already does suffix-match in its body. Without DA2.6 the plan would have shipped an invalid settings.json change.

### Adversarial review evidence

- Round 1 disposition: `/tmp/draft-plan-disposition-round-1.md`
- Round 2 disposition: `/tmp/draft-plan-disposition-round-2.md`
- Round 3 disposition: `/tmp/draft-plan-disposition-round-3.md`
- Round-2's blocker (DA2.2 — inlined block divergence) was caught by the adversarial review BEFORE the migration shipped. Without round 2, the plan would have shipped a 1000-line-duplication design that would drift over time.
