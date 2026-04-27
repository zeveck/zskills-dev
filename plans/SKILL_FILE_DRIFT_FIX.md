---
title: Skill-File Drift Fix — Runtime Config Resolution in Skill Bash Fences
created: 2026-04-25
status: active
---

# Plan: Skill-File Drift Fix

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Close the architectural gap left by `plans/DRIFT_ARCH_FIX.md`. That plan migrated CODE consumers (hooks, helper scripts) to runtime config-read and TEXT consumers (CLAUDE.md → `.claude/rules/zskills/managed.md`) to render-time fill + drift-warn. It declared itself a fix for "a systemic drift-bug class" but never mentioned a third category: **skill `.md` files containing executable bash fences** that the orchestrator (or dispatched subagents) execute literally.

A hardcode audit (verified independently by re-grep across 3 review rounds) found drift across **5 config-field categories** (initially the audit only swept 3, but refine round 3 caught 2 more — `.test-results.txt` and `scripts/port.sh` — that the original sweep missed):

- **52 sites**: `TZ=America/New_York` inside bash fences (25 plain + 27 inside `cat <<EOF | bash` heredocs). Config: `timezone`.
- **6 sites**: `npm run test:all` inside bash fences. Config: `testing.full_cmd`.
- **2 sites**: `npm start` inside bash fences. Config: `dev_server.cmd`.
- **8 sites**: `npm run test:all` in PROSE-IMPERATIVE form (each line read by re-grep + manual classification): `skills/commit/SKILL.md:169`, `skills/do/modes/direct.md:18`, `skills/do/SKILL.md:342`, `skills/doc/SKILL.md:282,314`, `skills/fix-issues/SKILL.md:755,1090`, `skills/qe-audit/SKILL.md:283`. The model executes them as instructions even though they're not in fences. Same drift class. Brought into scope refine round 3.
- **10 sites**: `$TEST_OUT/.test-results.txt` hardcoded filename suffix in bash fences: `skills/investigate/SKILL.md:208`, `skills/quickfix/SKILL.md:546-547`, `skills/run-plan/SKILL.md:843,859,1060,1095`, `skills/verify-changes/SKILL.md:307`, plus 2 in `run-plan/modes/pr.md:491,495` (in comments). Config: `testing.output_file`. Brought into scope refine round 3.
- **5 sites**: `bash scripts/port.sh` in skill fences: `skills/briefing/SKILL.md:129`, `skills/fix-report/SKILL.md:163,365`, `skills/manual-testing/SKILL.md:25`, `skills/verify-changes/SKILL.md:438`. After SCRIPTS_INTO_SKILLS_PLAN moves port.sh, these references break. Brought into scope refine round 3.
- **2 sites + schema**: `CO_AUTHOR="Claude Opus 4.7 (1M context) <noreply@anthropic.com>"` hardcoded default-then-config-override pattern at `skills/commit/SKILL.md:210` and `skills/quickfix/SKILL.md:603`. Skills drop the hardcoded default entirely; helper resolves `COMMIT_CO_AUTHOR` from config; the version-specific identity moves to `.claude/zskills-config.schema.json`'s default for `commit.co_author`, written by /update-zskills on install + backfilled into existing configs. Skills emit the Co-Authored-By trailer conditionally (skip if empty — supports consumer opt-out via blank config value). Single source of truth for the version string is the schema; updates flow naturally via schema bumps + /update-zskills --rerender.

**Total: 85 hardcoded references across 26 skill files** (52 TZ + 6 test-cmd EXEC + 2 dev-server EXEC + 8 PROSE-IMPERATIVE test-cmd + 10 testing.output_file + 5 scripts/port.sh + 2 co_author = exactly 85).

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
| 0 — Staleness gate (halt if SCRIPTS_INTO_SKILLS_PLAN not landed) | ⬚ | | |
| 1 — Canonical config-resolution helper resolves 5 vars (UNIT_TEST_CMD, FULL_TEST_CMD, TIMEZONE, DEV_SERVER_CMD, TEST_OUTPUT_FILE) | ⬚ | | |
| 2 — Migrate 85 hardcoded references across 7 categories (52 TZ + 6 test-cmd EXEC + 2 dev-server + 8 PROSE-IMPERATIVE + 10 output_file + 5 port.sh + 2 co_author) | ⬚ | | |
| 3 — Fix opinionated fallbacks in hooks (block-unsafe-project.sh:311 + sweep for others); sync test-infra detection list | ⬚ | | |
| 4 — Enforcement: test deny-list (extended fixture) + drift-warn hook extension + prose-imperative detection + allowlist comment convention | ⬚ | | |
| 5 — Verification + drift-regression test | ⬚ | | |

## Phase 0 — Staleness Gate

### Goal

Halt `/run-plan` cleanly if `plans/SCRIPTS_INTO_SKILLS_PLAN.md` has not landed. This plan places the new helper at `skills/update-zskills/scripts/zskills-resolve-config.sh` per SCRIPTS_INTO_SKILLS_PLAN's "Tier 1 = skill machinery in owning skill" framework. Before that plan lands, `skills/<owner>/scripts/` is not yet the canonical home for skill-machinery scripts and ~16 scripts still live at top-level `scripts/`. Landing this plan first would either (a) place the new helper at top-level `scripts/` (re-introducing the pollution that SCRIPTS_INTO_SKILLS_PLAN is fixing), or (b) pioneer a non-existent layout pattern — both wrong.

### Work Items

- [ ] 0.1 — **Frontmatter check.**

  ```bash
  FAIL=
  grep -F 'status: complete' plans/SCRIPTS_INTO_SKILLS_PLAN.md \
    || { echo "FAIL: prerequisite plan frontmatter not 'status: complete'" >&2; FAIL=1; }
  ```

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

- [ ] 1.2 — **Schema + install for `commit.co_author`** (refine round 3 redesign): ensure `.claude/zskills-config.schema.json` declares `commit.co_author` with a default value of `"Claude Opus 4.7 (1M context) <noreply@anthropic.com>"`. Verify `/update-zskills` Step C (config-merge logic) backfills this field into existing configs that lack it — per DRIFT_ARCH_FIX Phase 2 convention, missing fields get the schema default written on next /update-zskills run. Add a test under `tests/test-update-zskills-rerender.sh` (or equivalent) asserting backfill behavior for the `commit.co_author` field specifically.

- [ ] 1.3 — Author **`references/canonical-config-prelude.md`** in zskills repo root (reference doc; not installed downstream). Documents:
  - **Sourcing pattern** for skill fences (verbatim, copy-pasteable):

    ```bash
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    # vars now set: $UNIT_TEST_CMD $FULL_TEST_CMD $TIMEZONE $DEV_SERVER_CMD $TEST_OUTPUT_FILE $COMMIT_CO_AUTHOR
    ```

    **One-line preamble per fence.** Uses `--show-toplevel` so the helper resolves config from the current worktree's checkout (each worktree has its own `.claude/zskills-config.json` since the file is git-tracked). Resolves Round-3 finding 3.6. Helper script's internal config resolution also uses `--show-toplevel` so the caller doesn't need to pre-resolve any paths.

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

**One-line preamble per fence** (post round-3 simplification + post-Phase-0 path correction): `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`. Affected fences: ~40 (verified by `grep -cE '^\s*\`\`\`bash' skills/run-plan/SKILL.md` = 40, similar across other affected files; many fences hold multiple hardcodes that share ONE source line). Total new lines: ~40 (preamble) + ~60 (per-literal substitution) + ~32 (critical-path empty-checks) ≈ **130 lines added** across the migration, vs ~1000 with inline blocks.

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
- [ ] Worktree test: create a `git worktree add` from a fixture main repo; `cd` into the worktree; source the helper; assert vars resolve from the WORKTREE'S `.claude/zskills-config.json`, not the main repo's. Resolves Round-3 finding 3.6 verification.
- [ ] `references/canonical-config-prelude.md` exists and contains all 7 sections listed in WI 1.3.
- [ ] `update-zskills` install integrity test: run `/update-zskills` against a clean fixture; assert `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` is present in the rendered output. Resolves DA2.10 (downstream install behavior).
- [ ] All baseline tests still pass (current count: 826 from DRIFT_ARCH_FIX Phase 4 final).

### Dependencies

Phase 0 (staleness gate). Otherwise self-contained.

## Phase 2 — Migrate Hardcoded Literals

### Goal

Replace 85 hardcoded references across **5 categories** in skill `.md` files with `$VAR` references or post-migration paths; ensure each affected fence sources the canonical helper at its top.

### Work Items

- [ ] 2.1 — **Pre-migration enumeration.** Run `grep -rnB2 -E 'TZ=America/New_York|npm run test:all|npm start|\.test-results\.txt|scripts/port\.sh' skills/` and produce a hit-by-fence table: each row is one fence (file + opening-fence line) plus the literals it contains, the category (EXEC-FENCE, PROSE-IMPERATIVE, PROSE-DESCRIPTIVE, PROHIBITION, MIGRATION-TOOL), and the heredoc form (unquoted `<<TAG`, quoted `<<'TAG'`, or non-heredoc). Write to Phase 2 report. Spot-check round 2 found zero quoted heredocs in the TZ-migration set; WI 2.2 below treats this as the expected case and flags any contrary find.

- [ ] 2.2 — **Migration per fence.** For each fence in 2.1's table:
  - Add the **one-line preamble** at fence-top:

    ```bash
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    ```

    If the fence's heredoc-using code needs `$VAR` resolved before the heredoc opener (almost always — heredoc bodies expand vars at orchestrator bash time for unquoted `<<TAG`), the preamble at fence-top is the right placement. Worktree-aware via `--show-toplevel`.

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
    - `$TEST_OUT/.test-results.txt` → `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}` (informational consumer; the filename suffix isn't load-bearing for project semantics, only for hook-output-detection — fall back is safe).
    - `bash scripts/port.sh` → `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/port.sh"` (post-SCRIPTS_INTO_SKILLS_PLAN runtime path; matches the helper-source convention; no new helper var needed).

  - **PROSE-IMPERATIVE migration — exact list of 8 sites** (verified by reading each line; bullets/numbered-list/bold instructions to RUN the literal):
    - `skills/commit/SKILL.md:169` — "run `npm run test:all` before committing"
    - `skills/do/modes/direct.md:18` — "`npm run test:all` before committing if code was touched"
    - `skills/do/SKILL.md:342` — "**Run `npm run test:all`**"
    - `skills/doc/SKILL.md:282` — bullet "- `npm run test:all` if any code files were touched"
    - `skills/doc/SKILL.md:314` — bullet "**`npm run test:all` before committing**"
    - `skills/fix-issues/SKILL.md:755` — "5. Run `npm run test:all`"
    - `skills/fix-issues/SKILL.md:1090` — "**`npm run test:all` before every commit**"
    - `skills/qe-audit/SKILL.md:283` — "Run `npm run test:all` before committing"
    
    For each: replace the literal `npm run test:all` in the prose code-span with `$FULL_TEST_CMD`. Match `skills/run-plan/SKILL.md:181` convention. The model substitutes `$VAR` from prose at emission time when reading the instruction.

  - **co_author migration — 2 sites + schema/install**: `skills/commit/SKILL.md:210`, `skills/quickfix/SKILL.md:603`. Currently both hardcode `CO_AUTHOR="Claude Opus 4.7 (1M context) <noreply@anthropic.com>"` then override from config. Migration:
    - **Skills drop their hardcoded defaults entirely.** Source the helper at fence-top (already covered by 1-line preamble); use `$COMMIT_CO_AUTHOR` from the helper's resolution.
    - **Conditional trailer emission.** co_author is **informational metadata**, not critical-path — the Co-Authored-By trailer is optional. Skills append the trailer ONLY if `$COMMIT_CO_AUTHOR` is non-empty:

      ```bash
      if [ -n "$COMMIT_CO_AUTHOR" ]; then
        # append "Co-Authored-By: $COMMIT_CO_AUTHOR" to commit body
      fi
      ```

      No fail-loud on empty: blank value is a valid consumer opt-out (some downstreams may not want AI attribution in commit logs).
    - **Schema-default carries the version-specific identity.** `.claude/zskills-config.schema.json` sets the default for `commit.co_author` to `"Claude Opus 4.7 (1M context) <noreply@anthropic.com>"`. /update-zskills writes this default on fresh install AND backfills it into existing configs that lack the field (standard backfill behavior per DRIFT_ARCH_FIX Phase 2 convention). When Anthropic releases a new Claude version, zskills bumps the schema default; downstream `/update-zskills --rerender` (or next install) propagates the new value.
    - **Three resulting consumer states (per the design table):**
      - Field absent in config → /update-zskills backfills with schema default → trailer uses default
      - Field set to custom value → trailer uses custom
      - Field set to `""` (blank) → no trailer (consumer opt-out, intentional bypass)

  - **`scripts/port.sh` reference migration — 5 sites in fences**:
    - `skills/briefing/SKILL.md:129`, `skills/fix-report/SKILL.md:163,365`, `skills/manual-testing/SKILL.md:25`, `skills/verify-changes/SKILL.md:438`
    
    Each: replace `bash scripts/port.sh` with `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/port.sh"`. No new helper var; direct path to post-SCRIPTS_INTO_SKILLS_PLAN runtime location. Skip `update-zskills/SKILL.md:326,414,704` (MIGRATION-TOOL literals — the migration tool itself describes the antipattern by name).

  - **`testing.output_file` migration — 10 EXEC-FENCE sites**:
    - `skills/investigate/SKILL.md:208`, `skills/quickfix/SKILL.md:546-547`, `skills/run-plan/SKILL.md:843,859,1060,1095`, `skills/verify-changes/SKILL.md:307`, plus 2 in `run-plan/modes/pr.md:491,495` (commented bash). 
    
    Each: source the helper at fence-top (already covered by 2-line preamble); replace `$TEST_OUT/.test-results.txt` with `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}`. Informational consumer — fall back to literal `.test-results.txt` if config empty since the filename suffix isn't load-bearing for project semantics.

  - **Quoted heredocs (`<<'TAG'`)** — if 2.1's enumeration found any in the migration set: capture the resolved value into a shell var BEFORE the heredoc opener; embed the literal value into the heredoc body. (Expected count: 0.)

- [ ] 2.3 — **Mirror sync.** For every modified file in `skills/`, `cp` to `.claude/skills/`; verify with `diff -q` (silent = pass). Per `feedback_claude_skills_permissions`, batch the `cp` calls — don't intersperse with Edits.

- [ ] 2.4 — **Categorized re-audit.** Run the same grep as the original audit. Each hit must be in PROHIBITION or MIGRATION-TOOL or PROSE-DESCRIPTIVE category, NOT EXEC-FENCE. Document remaining-hit count per category in the phase report. Legitimate remaining literals (prohibition-by-name in `run-plan/SKILL.md:179`, migration-tool literal in `update-zskills/SKILL.md:404`) are expected. Resolves DA1.11.

- [ ] 2.5 — **End-to-end fixture test.** Add `tests/test-skill-file-drift.sh` (new file): create a temp dir with `.claude/zskills-config.json` containing `timezone: "Europe/London"` and `testing.full_cmd: "FIXTURE_FULL"`; copy a representative migrated skill fence into a runnable test harness; execute and assert the resolved values flow through correctly. Resolves DA2.10 / R2 round-2 concerns about cross-downstream behavior.

### Design & Constraints

**Migration discipline.** Each diff hunk should be the two-line preamble + literal substitution + empty-check guard. Do NOT reformat surrounding prose, change unrelated lines, or "improve" adjacent code.

**Per-fence cost.** ONE line per fence (preamble) + 1 line per literal substitution + 4 lines per critical-path empty-check. With ~40 affected fences, total new boilerplate: ~40 + ~60 + ~32 ≈ **130 lines added** across the migration. Compares to ~1000 lines under the rejected inline-block design. Resolves DA2.1 review-fatigue concern.

**Critical-path vs informational empty-handling.** Test-cmd and dev-server-cmd are critical (gate operations); empty config means fail-closed with explicit `/update-zskills` pointer. Timezone is informational (timestamp formatting); empty means UTC fallback with no error. Phase 1.2 documents both patterns; Phase 2.2 picks per literal.

**No allowlist exemptions added in Phase 2.** Every EXEC-FENCE hit is migrated. Phase 4 sets up the allowlist convention for legitimate prohibition-by-name / migration-tool sites that already exist.

### Acceptance Criteria

- [ ] `grep -rE 'TZ=America/New_York' skills/` returns hits ONLY in PROHIBITION/MIGRATION-TOOL/PROSE-DESCRIPTIVE categories (no EXEC-FENCE hits).
- [ ] `grep -rE 'npm run test:all' skills/` returns hits ONLY in non-EXEC-FENCE categories.
- [ ] `grep -rE 'npm start' skills/` returns hits ONLY in non-EXEC-FENCE categories.
- [ ] `for f in skills/**/*.md; do diff -q "$f" ".claude/$f"; done` returns no diffs.
- [ ] `bash tests/run-all.sh` passes (826 baseline + new from Phase 1).
- [ ] **Synthetic-fixture test** that exercises a migrated mode-file fence with `timezone: "Europe/London"` config and confirms the resulting timestamp uses London time, not New York.

### Dependencies

Phase 1 (canonical block must exist as a reference; inlining rule must be documented).

## Phase 3 — Fix `block-unsafe-project.sh:311` Opinionated Fallback + Sync Test-Infra Detection

### Goal

Remove the npm-specific fallback at `block-unsafe-project.sh:311` (verified present at commit f00e7c1). Adopt the three-case test-infra-detection tree that `verify-changes/SKILL.md` uses, and add a sync test asserting both consumers stay aligned.

### Work Items

- [ ] 3.1 — **Sweep ALL `${VAR:-default}` opinionated fallbacks in hooks** (refine round 3 anti-deferral). Run `grep -nE '\$\{[A-Z_]+:-[^}]+\}' hooks/*.template .claude/hooks/*.sh` to enumerate every parameter-expansion-with-default in the hook layer. For each hit: classify whether the default is opinionated (npm-specific, hardcoded path, etc.) or sensible (UTC timezone, empty string). Opinionated defaults get replaced with empty-string + three-case-tree. Currently-known instance: `block-unsafe-project.sh:311` `${FULL_TEST_CMD:-npm run test:all}`. Document any others found in the Phase 3 report; each gets its own three-case-tree fix (or substantively different justification, NOT "out of scope"). Remove the `:-npm run test:all` fallback and any other opinionated defaults; replace with empty-string default `${FULL_TEST_CMD}`. Mirror to `.claude/hooks/`.

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

  **Post-refine-round-3 fixture contents** (5 entries):
  ```
  TZ=America/New_York
  npm run test:all
  npm start
  .test-results.txt
  scripts/port.sh
  ```

  **Detection runs in TWO modes**:
  - **EXEC-FENCE detection** (default): hits inside ` ```bash `/`sh`/`shell` fences flagged unless an `<!-- allow-hardcoded -->` marker exempts them. Uses fence-state pseudocode below.
  - **PROSE-IMPERATIVE detection** (refine round 3): hits in PROSE outside fences, when the literal appears inside a code-span ` ` ` ` ` AND the line begins with a bullet (`^[[:space:]]*[-*]`) or numbered-list marker (`^[[:space:]]*[0-9]+\.`) AND the line contains an imperative verb (`Run|run|execute|invoke`). Same allowlist marker mechanism applies.

  For each literal in the fixture:
  - Grep recursively across `skills/**/*.md` (NOT `.claude/skills/*` — those are mirrors).
  - **Skip prose contexts**: only flag hits inside ` ```bash ` (or ` ```sh `, ` ```shell `, or ` ``` ` no-language) fences. Track fence state by line.
  - **Allowlist marker scope** (refined post-refine-DA1.3): the marker `<!-- allow-hardcoded: <literal> reason: ... -->` lives in MARKDOWN PROSE on the line IMMEDIATELY ABOVE a fence-opener. Such a marker exempts ALL hits of `<literal>` inside the immediately-following fence. The marker MUST NOT appear inside a fence (HTML comments aren't bash-valid and the test's expected scope is prose). Per-line markers (same-line or single-line-above the literal) are NOT supported — fence-scoped is simpler and matches realistic use cases (legitimate in-fence literals come in clusters: migration-tool greps, synthetic fixtures).

    Pseudocode:

    Pseudocode (post-refine-round-2 fixes — bash regex doesn't recognize `\<` as word-boundary so `<!--` is the literal pattern; capture extends to ` reason:` delimiter to support multi-token literals like `npm run test:all`):

    ```bash
    # Read fixture once into array for membership tests
    mapfile -t FORBIDDEN_LITERALS < <(grep -v '^#' tests/fixtures/forbidden-literals.txt | grep -v '^$')

    in_fence=0
    declare -A allowed_in_fence   # set of literals exempted in the current fence
    prev_lines=()                 # contiguous marker block immediately above fence-opener
    while IFS= read -r line; do
      ((line_no++))
      # Marker line: accumulate into prev_lines (reset prev_lines on any non-marker, non-blank line outside a fence)
      if [ "$in_fence" -eq 0 ]; then
        if [[ "$line" =~ ^[[:space:]]*[\<]!--[[:space:]]+allow-hardcoded:[[:space:]]+(.+)[[:space:]]+reason:.*[-][-][\>][[:space:]]*$ ]]; then  # character classes [<] [>] work in both inline-regex and $var-regex contexts (verified empirically); plain \< / quoted "<!--" forms have inconsistent behavior across bash versions
          # Trim trailing whitespace from captured literal
          captured="${BASH_REMATCH[1]}"
          captured="${captured%"${captured##*[![:space:]]}"}"
          prev_lines+=("$captured")
        elif [[ "$line" =~ ^[[:space:]]*\`\`\`(bash|sh|shell)?[[:space:]]*$ ]]; then
          # Fence-opener: marker block (if any) becomes the exemption set for this fence
          in_fence=1
          allowed_in_fence=()
          for lit in "${prev_lines[@]}"; do allowed_in_fence["$lit"]=1; done
          prev_lines=()
          continue
        else
          # Any other non-blank line resets the marker block
          [[ -n "$line" ]] && prev_lines=()
        fi
        continue
      fi
      # Inside a fence
      if [[ "$line" =~ ^[[:space:]]*\`\`\`[[:space:]]*$ ]]; then
        in_fence=0
        allowed_in_fence=()
        prev_lines=()
        continue
      fi
      # Check forbidden literals
      for literal in "${FORBIDDEN_LITERALS[@]}"; do
        if [[ "$line" == *"$literal"* ]] && [ -z "${allowed_in_fence[$literal]:-}" ]; then
          echo "DRIFT: $skill_file:$line_no contains '$literal' inside a bash fence without an allow-hardcoded marker above the fence-opener."
          FAIL=1
        fi
      done
    done < "$skill_file"
    ```

    Resolves R2.1 (prose false-positives), round-2 / refine-DA1.3 (marker-above-fence-opener edge case), refine-R1.4 (line-1 boundary handled implicitly — `prev_lines` initialized empty), refine-2.1 (`<!--` literal not `\<!--`), refine-2.2 (multi-token literal capture via ` reason:` delimiter).
  - **For in-fence hits**, check whether the same line OR the line immediately above contains a marker `<!-- allow-hardcoded: <literal> reason: ... -->` that names the SAME literal verbatim. (Note: bash fences don't typically contain HTML comments; the allowlist marker would be on the line above the fence start. Test handles this by extending the "line above" lookup to skip back over the fence-opener line.) Use a `[ "$line_no" -gt 1 ]` guard before checking the previous line to avoid sed errors at file-start (resolves DA2.6).
  - Failing test output: `DRIFT: skills/<file>:<line> contains '<literal>' inside a bash fence without an allow-hardcoded marker. Replace with $VAR (preferred) or add the marker if legitimately required.`
  - At the top of the test section, document the extension process: "When adding a new config field whose value could appear in skill files, add the antipattern literal to `tests/fixtures/forbidden-literals.txt`. Both the test and `hooks/warn-config-drift.sh` read from this file."

- [ ] 4.2 — **Drift-warn hook extension.** Edit `hooks/warn-config-drift.sh` (and `.claude/hooks/warn-config-drift.sh`). Structurally:

  ```bash
  # ... existing config-file matcher ...

  # New: skill-file matcher
  if [[ "$FILE_PATH" =~ skills/.*\.md$ ]]; then
    for literal in "TZ=America/New_York" "npm run test:all" "npm start"; do
      while IFS= read -r line_no_match; do
        # ... extract line number; check for allow-hardcoded marker on same/prev line ...
        # ... if no marker: emit WARN to stderr with file:line + literal ...
      done < <(grep -nF "$literal" "$FILE_PATH")
    done
  fi
  ```

  Add the new block AFTER the existing config-matcher block to keep the two concerns separate (resolves DA1.9). Read the literal list from `tests/fixtures/forbidden-literals.txt` — same fixture file Phase 4.1's test reads (single source of truth; resolves DA1.5 / refine-DA1.5).

- [ ] 4.3 — **Settings.json wiring.** Add the new PostToolUse matcher to `.claude/settings.json`: matcher `skills/.*\.md$` pointing at `warn-config-drift.sh`. Use the agent-driven Read+Edit pattern DRIFT_ARCH_FIX Phase 2 introduced (NOT a wholesale rewrite of settings.json).

- [ ] 4.4 — **Allowlist convention** documented in `.claude/rules/zskills/managed.md` (zskills-managed rule, ships to downstream). One-paragraph rule referencing the format spec in `references/canonical-config-prelude.md`. Two worked examples (prohibition-by-name and migration-tool literal).

- [ ] 4.5 — **Test cases for WI 4.2.** Synthetic Edit event on `skills/foo/SKILL.md` (in a temp fixture) adding a forbidden literal → assert WARN line in stderr. Synthetic Edit adding the same literal WITH the allowlist marker → assert no WARN. Tests live in `tests/test-hooks.sh`.

### Design & Constraints

**Three layers, not one.** Test deny-list catches at CI time (strong gate, blocks merge). Drift-warn hook catches at edit time (real-time nudge, non-blocking). Allowlist comments are inspectable in raw markdown next to the literal (low ceremony for legitimate exemptions). Combined: incident on commit + nudge during editing + low-friction exemption mechanism.

**Forbidden-literal list maintenance.** Single source of truth in `tests/fixtures/forbidden-literals.txt` (refine round 1 fix). Both the test (Phase 4.1) and the drift-warn hook (Phase 4.2) read this file at runtime. Config-derived auto-list rejected: per-downstream config means different literals would be deny-listed in different downstreams, breaking shared skill-file consistency. Post-refine-round-3 expanded list contents:

```
# tests/fixtures/forbidden-literals.txt
TZ=America/New_York         # use ${TIMEZONE:-UTC}
npm run test:all            # use $FULL_TEST_CMD
npm start                   # use $DEV_SERVER_CMD
.test-results.txt           # use ${TEST_OUTPUT_FILE:-.test-results.txt}
scripts/port.sh             # use $CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/port.sh
```

**Allowlist scope.** The marker exempts ONE literal on the same line OR the line immediately above. Reviewer can inspect markers in PR diff. Misuse is visible.

**Hook-skill collision concern** (per `feedback_prefer_inspectable_skill_output_over_permissive_hook_heuristics`). The drift-warn hook is non-blocking (WARN only); cannot block legitimate edits. The test deny-list IS blocking but is inspectable — exemption requires a literal allowlist comment, not a heuristic bypass.

### Acceptance Criteria

- [ ] `bash tests/run-all.sh` includes the new deny-list section asserting zero unmarked-hardcode regressions.
- [ ] Drift-warn hook test cases pass (synthetic Edit with/without allowlist marker).
- [ ] `.claude/settings.json` shows the new PostToolUse matcher.
- [ ] `.claude/rules/zskills/managed.md` documents the allowlist convention with at least 2 worked examples.
- [ ] Manual smoke test: in a live session, edit a skill file to add `TZ=America/New_York` literal; observe the WARN in session stderr.

### Dependencies

Phase 1 (allowlist marker format spec must exist in canonical-prelude doc); Phase 2 (deny-list test must pass against post-migration baseline). **Strict ordering**: Phase 4 lands AFTER Phase 2 is fully complete. Installing the drift-warn hook before Phase 2 is done would produce WARN spam during the migrating agent's intermediate states (one fence migrated, another not yet). Resolves DA2.8.

## Phase 5 — Verification + Drift-Regression Test

### Goal

End-to-end verification + cross-reference DRIFT_ARCH_FIX with the gap closure.

### Work Items

- [ ] 5.1 — Run `/verify-changes branch` on the feature branch. All 4 prior phases' commits inspected for diff correctness, scope assessment, mirror parity. Resolve any flags.

- [ ] 5.2 — **Two-sided drift-regression test** in `tests/test-skill-conformance.sh`:
  - **Negative side** (already in Phase 4.1): no unmarked forbidden literals.
  - **Positive side** (NEW in 5.2): the test enumerates `MIGRATED_SKILLS` dynamically — any skill `.md` file that contains a `$VAR` reference matching `\$\{?(UNIT_TEST_CMD|FULL_TEST_CMD|TIMEZONE|DEV_SERVER_CMD)\}?` (covers both bare `$VAR` and braced/parameter-expansion `${VAR:-default}` forms — Phase 2.2's migration produces `${TIMEZONE:-UTC}`, so the bare-only regex would miss it; refine-round-1 DA1.4) is required to also contain `zskills-resolve-config.sh` (the helper-source filename, matched anywhere in the file). Dynamic detection avoids maintaining a hardcoded list (resolves Round-3 finding 3.9). Together with the negative side, this catches both regression modes: literal restored (negative side fails) or helper-source removed leaving dangling `$VAR` (positive side fails).

- [ ] 5.3 — **Cross-reference DRIFT_ARCH_FIX.** Append to `plans/DRIFT_ARCH_FIX.md` (after its "Plan Quality" section) a one-line "see also" pointer: *"This plan migrated CODE consumers and TEXT consumers but did not address skill `.md` files containing bash fences. That gap is closed by `plans/SKILL_FILE_DRIFT_FIX.md`."* Resolves the user's frustration about banner-overstating without rewriting the original plan's history.

- [ ] 5.4 — Update `plans/PLAN_INDEX.md` to mark this plan as Active during execution and Complete after landing. Add the new file to the index per the existing convention.

- [ ] 5.5 — Add a one-paragraph rule to `.claude/rules/zskills/managed.md` (or extend Phase 4.4's allowlist-convention paragraph): *"Skill `.md` files MUST resolve config-derived values via the canonical block in `references/canonical-config-prelude.md`. Hardcoded literals trigger the deny-list test (`tests/test-skill-conformance.sh`) and the drift-warn hook (`hooks/warn-config-drift.sh`). Exemptions require an inspectable `<!-- allow-hardcoded: ... -->` marker per the format spec."*

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
- **`scripts/port.sh` skill-fence references (5 sites)** — original audit missed this category; brought into Phase 2 (replace with post-SCRIPTS_INTO_SKILLS_PLAN runtime path).
- **Hook fallback sweep beyond `block-unsafe-project.sh:311`** — Phase 3 WI extended to grep for ALL `${VAR:-default}` patterns in `hooks/*.template` and `.claude/hooks/*.sh`, not just the one known instance.

## Risks & Mitigations

- **Risk**: Phase 2's 85-site mechanical migration touches 26 files; review fatigue. **Mitigation**: 1-line preamble + per-literal substitution per fence keeps diffs compact (estimated 130-200 lines added across migration vs ~1000 with the rejected inline-block design); Phase 5.1 `/verify-changes branch` is independent fresh-eyes review.
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
| 0 | (didn't exist) | Staleness gate, 5 work items, 4 anchor pairs + CHANGELOG + export checks | NEW phase added in post-finalize revision (2026-04-25); strengthened in /refine-plan round 1 |
| 1 | Helper at top-level `scripts/`, 1-line preamble using `git rev-parse --show-toplevel` | Helper at `skills/update-zskills/scripts/`, 1-line preamble using `$CLAUDE_PROJECT_DIR` | Location relocated (post-finalize); sourcing convention aligned with SCRIPTS_INTO_SKILLS_PLAN (refine round 1) |
| 2 | 3 work items (timezone migration, test-cmd migration, dev-server migration as separate WIs) | 5 work items, consolidated by-fence with empty-check guards; fence-state pseudocode for AC verification | Migration discipline tightened in /draft-plan round 1-3 |
| 3 | Three-case tree replacement at line 311 + sync test | Same scope; sync mechanism extracted to `tests/fixtures/test-infra-patterns.txt` shared file | /draft-plan round 2: explicit shared-fixture file pattern |
| 4 | Test deny-list + drift-warn extension + allowlist comments; FORBIDDEN_LITERALS list defined twice | Same scope; `tests/fixtures/forbidden-literals.txt` shared file; pseudocode rewritten with character-class `[<]` and `[>]` regex (refine round 2 fix for bash quoting) | /refine-plan round 1-2: shared-fixture file + regex robustness |
| 5 | Two-sided drift-regression test, positive-side regex `\$(VAR)` | Same scope; positive-side regex expanded to `\$\{?(VAR)\}?` to match braced forms | /refine-plan round 1: regex covers `${TIMEZONE:-UTC}` migration output |

## Plan Review

**Drafting + refinement process:** `/draft-plan` 3 rounds (2026-04-25) → user-driven post-finalize revision (Phase 0 + relocation, 2026-04-25) → `/refine-plan` 2 rounds (2026-04-26).

**Convergence:** Converged at refine round 2.

**Remaining concerns:** None blocking.

### Round History

| Round | Reviewer | DA | Substantive | Resolved | Outcome |
|-------|----------|----|-------------|----------|---------|
| draft-1 | 11 (3 blocker + 6 major + 2 minor) | 11 (2 blocker + 4 critical + 5 major) | 16 (post-dedup) | 15 fixed + 1 justified | Architectural reframe: rejected "preflight propagates `$VAR`" assumption |
| draft-2 | 5 | 13 | 18 (post-dedup) | 15 fixed + 3 justified | Architectural reframe: adopted sourced helper script (rejected inline-block design) |
| draft-3 | (combined) | (combined) | 9 | 7 fixed + 2 justified | Specification corrections (`.claude/scripts/` ref, `--show-toplevel` worktree-correctness) |
| refine-1 | 8 | 6 | 7 | 7 fixed | Sourcing path → `$CLAUDE_PROJECT_DIR` (convention alignment); Phase 0 strengthened; positive-side regex expanded; FORBIDDEN_LITERALS shared file; fence-state pseudocode rewritten; baseline test count 815→826 |
| refine-2 | (combined) | (combined) | 2 | 2 fixed | Pseudocode bugs surfaced from refine-1 fix: `\<` non-portable across bash regex contexts → character class `[<]`; multi-token literal capture via ` reason:` delimiter |
| refine-3 | 8 (2 critical + 2 major + 2 minor + 2 nit) | 9 (2 critical + 4 major + 3 minor) | 13 (post-dedup) | 12 fixed + 1 not-reproduced (DA3.6 regex; verified empirically) | **Anti-deferral pass.** User-driven: caught the plan deferring PROSE-IMPERATIVE migration ("model doesn't execute these as bash" was wrong) and missing two config-field categories the original audit never swept. Brought into scope: 8 PROSE-IMPERATIVE sites (`npm run test:all` instructions, exact list per re-grep + manual classification); 10 `.test-results.txt` hardcodes (testing.output_file); 5 `scripts/port.sh` references (will break post-SCRIPTS_INTO_SKILLS_PLAN); 2 `co_author` default-overrides (Claude-version drift). Helper extended to resolve TEST_OUTPUT_FILE; fixture file expanded to 5 entries; Phase 4 deny-list extended to detect PROSE-IMPERATIVE outside fences (bullet + code-span + imperative-verb heuristic); Phase 3 sweeps ALL hook fallbacks not just the one known instance. Stale prose at lines 313, 422, 484 fixed. **Total scope grew from 60 → 85 hardcoded references across 7 categories.** Verified clean: `dev_server.main_repo_path`, `ui.auth_bypass`, `agents.min_model` (0 hits each in skill bash fences). |

**Total findings across all rounds: 65. Resolved: 58 fixed, 7 justified. Zero deferred or ignored.**

### Notable catches

- **Empirical verification** (draft-1) prevented shipping a fundamentally broken architecture (bash shell state non-persistence).
- **Inlined-block divergence blocker** (draft-2) prevented shipping ~1000 lines of duplicated boilerplate.
- **Worktree-config bug** (draft-3) caught `--git-common-dir` vs `--show-toplevel` distinction.
- **Sourcing-path convention violation** (refine-1) caught inconsistency with SCRIPTS_INTO_SKILLS_PLAN's `$CLAUDE_PROJECT_DIR` rule (lines 175-195) — `--show-toplevel` would have worked in practice but violated the locked convention; future divergence risk.
- **Bash regex quoting quirk** (refine-2) — `\<` works in inline regex but fails in `$var` regex; character class `[<]` is portable across both contexts. Verified empirically with `[[ '<!-- foo' =~ ... ]]` in both forms.

### Adversarial review evidence

- Round 1 disposition: `/tmp/draft-plan-disposition-round-1.md`
- Round 2 disposition: `/tmp/draft-plan-disposition-round-2.md`
- Round 3 disposition: `/tmp/draft-plan-disposition-round-3.md`
- Round-2's blocker (DA2.2 — inlined block divergence) was caught by the adversarial review BEFORE the migration shipped. Without round 2, the plan would have shipped a 1000-line-duplication design that would drift over time.
