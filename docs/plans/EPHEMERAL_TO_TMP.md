---
title: Route ephemeral test outputs to /tmp
created: 2026-04-16
status: complete
---

# Plan: Route ephemeral test outputs to /tmp

## Overview

Move ephemeral test-output files (`.test-results.txt`, `.test-baseline.txt`, future `.test-*.txt` variants) out of the working tree to `/tmp/zskills-tests/<worktree-basename>/` so they never appear in any `git status` of any repo using zskills. This is the structural fix promised by commit 412b097 (which added wildcard `.gitignore` patterns as a stopgap). Also gitignore `.claude/logs/` so agent log artifacts don't clutter the working tree.

The refactor touches:
- `CLAUDE.md` (convention prose) **and** `CLAUDE_TEMPLATE.md` (downstream-install template)
- Five skill `SKILL.md` files and their `.claude/skills/` mirrors (`run-plan`, `verify-changes`, `investigate`, `fix-issues`, `update-zskills`)
- One hook + its installed copy (`hooks/block-unsafe-project.sh.template` + `.claude/hooks/block-unsafe-project.sh`)
- `scripts/land-phase.sh` (adds `/tmp` dir cleanup)
- `tests/test-hooks.sh` (adds regression for the new `/tmp` cleanup)
- `.gitignore` (removes 412b097 wildcards; adds `.claude/logs/`)

**What we DO NOT change:**
- `.claude/zskills-config.json` / `config/zskills-config.schema.json` — no new fields. The convention lives in `CLAUDE.md` prose only; it does not need a config flag because nothing reads a config flag to compute the path today. (Round-1 adversarial review revealed that adding an `output_dir` field would require an extractor in `skills/update-zskills/SKILL.md:98`, making the plan larger with no functional benefit.)
- Historical plan docs under `plans/` — they reference the old path in frozen narrative and are out of scope per the user's acceptance grep (`skills/ CLAUDE.md .claude/skills/`).
- The `EPHEMERAL_FILES` array in `scripts/land-phase.sh:61` — it remains as a **contract-violation canary** (see Phase 3 design note).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Update CLAUDE.md + CLAUDE_TEMPLATE.md with canonical idiom | ✅ Done | `56780f9` | Landed; verifier report, tests 235/235 |
| 2 — Update skill recipes (run-plan, verify-changes, investigate, fix-issues, update-zskills) + mirrors | ✅ Done | `d60e6eb` | 8 files, 23 TEST_OUT refs in run-plan |
| 3 — Update hook message + land-phase.sh /tmp cleanup + regression test | ✅ Done | `66d9138` | 4 files, test count unchanged |
| 4 — Pre-gate clean-tree check + remove wildcard .gitignore + gitignore .claude/logs | ✅ Done | `86ca2e7` | Pre-gate passed, wildcards removed, .claude/logs/ added |

## Phase 1 — Establish the canonical idiom in CLAUDE.md and CLAUDE_TEMPLATE.md

### Goal
Document the single canonical idiom for writing test output in both `CLAUDE.md` (this project's guidance) and `CLAUDE_TEMPLATE.md` (the template that `/update-zskills` copies into downstream projects).

### Work Items

- [ ] **Edit `CLAUDE.md:31-34`** — replace the current convention block verbatim with:

  ```markdown
  **Capture test output to a file, never pipe.** Route test output OUT of
  the working tree so it never shows up in `git status`. The canonical idiom
  is:

  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  <test-cmd> > "$TEST_OUT/.test-results.txt" 2>&1
  ```

  Then read `"$TEST_OUT/.test-results.txt"` to inspect failures. Never pipe
  through `| tail`, `| head`, `| grep` -- it loses output and forces re-runs.
  `/tmp/zskills-tests/` is per-worktree-basename, so parallel pipelines do
  not collide. `scripts/land-phase.sh` removes the per-worktree dir on
  successful landing. Always compute `$TEST_OUT` from `$(pwd)` AFTER you
  have `cd`-ed into the correct repo/worktree root; or derive it from an
  explicit `$WORKTREE_PATH` the caller passes you (never assume cwd if you
  were just handed a path).
  ```

- [ ] **Edit `CLAUDE_TEMPLATE.md:42-45`** — replace the template's placeholder-form block with a version that HARDCODES `.test-results.txt` (previously `{{TEST_OUTPUT_FILE}}`). Hardcoding is consistent with how this plan already hardcodes the `/tmp/zskills-tests/...` path; it also eliminates ambiguity because `/update-zskills`'s placeholder substitution is agent-prose-driven (see `skills/update-zskills/SKILL.md:413-438`), and `{{TEST_OUTPUT_FILE}}` is NOT listed in the explicit placeholder detection at lines 413-421 — relying on it risks a literal `{{TEST_OUTPUT_FILE}}` leaking into downstream `CLAUDE.md`. New template text:

  ```markdown
  **Capture test output to a file, never pipe.** Route test output OUT of
  the working tree so it never shows up in `git status`. The canonical idiom
  is:

  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  {{FULL_TEST_CMD}} > "$TEST_OUT/.test-results.txt" 2>&1
  ```

  Then read `"$TEST_OUT/.test-results.txt"` to inspect failures. Never pipe
  through `| tail`, `| head`, `| grep` -- it loses output and forces re-runs.
  ```

  `/update-zskills` already reliably handles `{{FULL_TEST_CMD}}` (it's explicitly listed in the substitution instructions at `skills/update-zskills/SKILL.md:419-421`). The filename `.test-results.txt` and the `/tmp/zskills-tests/$(basename "$(pwd)")` path are hardcoded — every zskills-managed project shares the same filename and tmp layout.

- [ ] **Verify no other file in the repo documents the old convention as guidance.** Run `grep -rEn "Capture test output to a file" .` and confirm only `CLAUDE.md` and `CLAUDE_TEMPLATE.md` match. If any other file does (e.g., a skill that reiterates the rule), add it to Phase 2's scope instead of Phase 1.

### Design & Constraints

- **Canonical idiom is Option A (inline 3 lines).** Alternative Option B (a helper script `scripts/test-out.sh` that echoes the dir) was considered and rejected — extra shell-out, extra file to install in every worktree, no meaningful savings.
- **Why `$(basename "$(pwd)")`** — matches what `scripts/land-phase.sh` already uses on the cleanup side (`basename "$WORKTREE_PATH"`). Inside a worktree cwd IS the worktree path, so the basename aligns. In the main repo cwd is the repo root, basename is `zskills`, which is fine — main-repo test runs get `/tmp/zskills-tests/zskills/`.
- **"Compute $TEST_OUT AFTER you cd" guidance** — this is the fix for the Round 1 verify-agent cwd bug. The CLAUDE.md block explicitly warns agents to not compute `$TEST_OUT` before `cd`-ing into the target tree. Phase 2 enforces this at each callsite.
- **`CLAUDE_TEMPLATE.md` substitution.** `/update-zskills` copies `CLAUDE_TEMPLATE.md` → target project's `CLAUDE.md` with placeholder substitution. The new text uses only `{{FULL_TEST_CMD}}`, which has explicit substitution instructions at `skills/update-zskills/SKILL.md:419-421`. We intentionally DROP the previous `{{TEST_OUTPUT_FILE}}` placeholder (it was not in the update-zskills detection/substitution list, risking literal leakage) and hardcode `.test-results.txt` instead — consistent with how this plan already hardcodes `/tmp/zskills-tests/$(basename "$(pwd)")`.
- **Config schema left alone.** No `output_dir` field added. Rationale (from R2+DA4+DA5 in Round 1): `skills/update-zskills/SKILL.md:98` currently has a regex extractor only for `output_file`; adding `output_dir` without adding an extractor silently drops the field on re-install. Adding the extractor doubles the surface area of this plan for no behavioural gain. Keep the config simple; the convention lives in CLAUDE.md prose.

### Acceptance Criteria

- [ ] `CLAUDE.md:31-34` (or surrounding lines if drift occurs) contains the new convention block verbatim.
- [ ] `CLAUDE_TEMPLATE.md:42-45` (or surrounding lines) contains the new block with the `{{FULL_TEST_CMD}}` placeholder and a HARDCODED `.test-results.txt` filename (no `{{TEST_OUTPUT_FILE}}` placeholder).
- [ ] `grep -n 'TEST_OUTPUT_FILE' CLAUDE_TEMPLATE.md` returns zero matches (the placeholder is fully removed).
- [ ] `grep -rEn "Capture test output to a file" .` returns matches ONLY in `CLAUDE.md` and `CLAUDE_TEMPLATE.md` (no skill SKILL.md duplicates the rule as its own guidance — if one does, update it in Phase 2).
- [ ] `grep -n "test-results.txt" CLAUDE.md CLAUDE_TEMPLATE.md` returns only the new idiom references.
- [ ] `bash tests/run-all.sh` passes with all green. (No test asserts on CLAUDE.md text today, so count is unchanged — prose edits are invisible to the suite.)

### Dependencies

None. Phase 1 is standalone and establishes the idiom used by Phases 2-4.

## Phase 2 — Update skill recipes and their `.claude/skills/` mirrors

### Goal

Rewrite every `.test-*.txt` callsite in `skills/` to use the canonical idiom, and byte-for-byte mirror each change to `.claude/skills/`. For agents dispatched by other agents (the orchestrator → verifier handoff), the dispatcher must pass an explicit worktree path so the callee does not guess.

### Work Items

- [ ] **`skills/run-plan/SKILL.md`** — update these sites (verify exact lines with `grep -n` before editing; earlier edits may have drifted line numbers):

  - **Line 608-609 (hygiene list)** — KEEP `.test-baseline.txt` and `.test-results.txt` in the list as a **contract-violation deterrent** (Round 1 finding DA2). Update surrounding prose to:
    ```
    files `.worktreepurpose`, `.zskills-tracked`, and `.landed` are worktree
    lifecycle markers and must stay UNTRACKED throughout the run.

    Test output lives OUTSIDE the worktree, at `/tmp/zskills-tests/<worktree-
    basename>/` (see CLAUDE.md). The filenames `.test-results.txt` and
    `.test-baseline.txt` should NEVER appear in the worktree at all; if they
    do, a stale writer leaked them, and `scripts/land-phase.sh` treats any
    git-tracked version as a landing-time error (a canary for contract
    violations — not a normal-path cleanup).
    ```

  - **Line 690 (impl recipe)** — replace the single-line test command with the three-line idiom:
    ```
    >    TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
    >    mkdir -p "$TEST_OUT"
    >    npm run test:all > "$TEST_OUT/.test-results.txt" 2>&1
    ```

  - **Line 696 (impl recipe prose)** — `read \`.test-results.txt\`` → `read \`"$TEST_OUT/.test-results.txt"\``.

  - **Line 702 (retry recipe)** — same three-line replacement as line 690.

  - **Line 811 (orchestrator baseline)** — replace `$FULL_TEST_CMD > .test-baseline.txt 2>&1 || true` with:
    ```bash
    TEST_OUT="/tmp/zskills-tests/$(basename "$WORKTREE_PATH")"
    mkdir -p "$TEST_OUT"
    $FULL_TEST_CMD > "$TEST_OUT/.test-baseline.txt" 2>&1 || true
    ```
    Use `$WORKTREE_PATH` (already in scope at this site) — NOT `$(pwd)` — because the orchestrator runs outside the worktree at this point.

  - **Line 898-925 (verifier dispatch bullet and baseline-compare bullet)** — this is the CRITICAL Round 1 DA1 fix. Update the bullet at ~line 900 that says "The **worktree path** from Phase 2 (so it can read files and run tests there via `cd <worktree-path> && npm run test:all`)" to read:
    ```
    The **worktree path** from Phase 2 (so it can read files and run tests
    there). The verifier must run tests via:

    ```bash
    cd <worktree-path>
    TEST_OUT="/tmp/zskills-tests/$(basename "<worktree-path>")"
    mkdir -p "$TEST_OUT"
    npm run test:all > "$TEST_OUT/.test-results.txt" 2>&1
    ```

    Note: compute `$TEST_OUT` from the worktree-path LITERAL you were handed,
    NOT from `$(pwd)` at prompt-entry time — the orchestrator dispatches you
    without `isolation`, so your initial cwd is the orchestrator's (typically
    main), and a pre-cd `$(pwd)` would yield the wrong basename and miss the
    baseline.

    Orchestrator-runtime note: when the orchestrator constructs the verifier
    prompt, it substitutes the literal string `<worktree-path>` with the
    actual worktree path BEFORE dispatching. The verifier sees a fully-
    substituted prompt — no placeholder parsing on its side. Both orchestrator
    baseline capture (line 811) and verifier `$TEST_OUT` derivation MUST use
    `basename` of the SAME path literal, so the baseline and the results land
    in the same `/tmp/zskills-tests/<name>/` bucket.
    ```

    Then update the `.test-baseline.txt` / `.test-results.txt` references in the baseline-compare bullets (lines ~907-920) to use `"$TEST_OUT/.test-baseline.txt"` and `"$TEST_OUT/.test-results.txt"`.

  - **Line 2012, 2016 (code-comment examples)** — update the example command to the new idiom.

- [ ] **`skills/verify-changes/SKILL.md`** — update:
  - **Line 208 (primary recipe)** — replace one-liner with three-line idiom (`$(pwd)`-based; `/verify-changes` runs in the repo/worktree the user invokes it in).
  - **Line 211, 215, 235 (prose references)** — `.test-results.txt` → `"$TEST_OUT/.test-results.txt"`.
  - **Line 246 (final gate)** — replace one-liner with three-line idiom.

- [ ] **`skills/investigate/SKILL.md`** — update:
  - **Line 206 (recipe)** — three-line idiom.
  - **Line 208 (prose)** — `Read \`.test-results.txt\`` → `Read \`"$TEST_OUT/.test-results.txt"\``.

- [ ] **`skills/fix-issues/SKILL.md`** — KEEP the grep filter at line 1074 unchanged (Round 1 DA7 finding). Update only the hardcoded cleanup reference at line 1078:
  ```
  rm -f "<worktree>/.landed" "<worktree>/.worktreepurpose" \
        "<worktree>/.test-results.txt"
  ```
  becomes:
  ```
  rm -f "<worktree>/.landed" "<worktree>/.worktreepurpose"
  ```
  (Remove the `<worktree>/.test-results.txt` line — that file lives in `/tmp` now. `scripts/land-phase.sh` handles `/tmp` cleanup in Phase 3; auto-remove does not need to duplicate it.)
  The filter at line 1074 stays as-is — it's a defense for the case where a stale writer leaks the file into a worktree and a cleanup pass needs to tolerate it while still detecting real work.

- [ ] **`skills/update-zskills/SKILL.md`** — line 162 is a config-example snippet showing `"output_file": ".test-results.txt"`. Since Phase 1 explicitly chose NOT to change the config schema, this line stays as-is. Verify by grep that no other site in `update-zskills/SKILL.md` references the old test-output path in a prose-guidance context. If found, update.

- [ ] **Mirror every change to `.claude/skills/<skill>/SKILL.md`.** After editing each `skills/<skill>/SKILL.md`, apply the exact same edit to the mirror. Run `diff -u skills/<skill>/SKILL.md .claude/skills/<skill>/SKILL.md` — if output is non-empty, the mirror is drift, apply the fix. The Edit tool: call it twice, once for each path.

### Design & Constraints

- **Line numbers are advisory.** Each Work Item lists the research-time line number; the implementing agent MUST `grep -n` each target pattern fresh before editing. Previous edits within the same phase will drift line numbers.
- **Orchestrator-passed worktree path.** The verifier dispatch fix (Round 1 DA1) is the single most important correctness change: any agent dispatched to a worktree must receive the worktree path as an explicit argument/variable and derive `$TEST_OUT` from that literal, not from `$(pwd)` at prompt-entry.
- **Fix-issues filter is a defense.** The grep at line 1074 filters `\.test-results` out of the "uncommitted work detector" so that a stale writer's leak doesn't block auto-removal of an otherwise-clean worktree. Removing that filter would mean any unlucky leak deadlocks auto-cleanup. Keep it.
- **`plans/` is intentionally frozen.** Historical plans (`plans/TRACKING_FIX.md`, `plans/EXECUTION_MODES.md`, etc.) contain runnable recipes with the old path. These are documentation of what was done — not live guidance — and re-executing them outside `/run-plan` is not a supported workflow. The acceptance grep is scoped to `skills/ CLAUDE.md .claude/skills/` per the user's prompt. We accept that if someone copy-pastes `> .test-results.txt 2>&1` out of a historical plan, the file will appear in `git status` (now that the wildcard `.gitignore` is gone) — that's a correct signal, not a regression.

### Acceptance Criteria

- [ ] `grep -rEn '\.test-(results|baseline|output).*\.txt' skills/ CLAUDE.md .claude/skills/ CLAUDE_TEMPLATE.md` returns ONLY:
  - References inside the new idiom (`"$TEST_OUT/.test-results.txt"` or `"$TEST_OUT/.test-baseline.txt"`)
  - The intentional hygiene-list prose at `skills/run-plan/SKILL.md:608-609` and mirror (names appear as bare `.test-*.txt` but they are in a `files must stay UNTRACKED` context, not a writable recipe)
  - The intentional fix-issues filter at line 1074 and mirror (grep pattern `\.test-results`, used to tolerate leaks)
  - The hardcoded `.test-results.txt` in the CLAUDE_TEMPLATE.md new idiom block (intentional — see Phase 1)

  A reviewer can scan each hit and classify it "intentional" without ambiguity.
- [ ] `diff -rq skills/ .claude/skills/` shows only the pre-existing extras (`.claude/skills/playwright-cli`, `.claude/skills/social-seo`) and no new drift.
- [ ] `grep -n "TEST_OUT" skills/run-plan/SKILL.md` shows occurrences at: impl recipe (×2), retry recipe, baseline capture, verifier dispatch bullet, verifier baseline-compare bullets, and code-comment example at line 2012+. At least 6 occurrences.
- [ ] `diff -u skills/run-plan/SKILL.md .claude/skills/run-plan/SKILL.md` → no output. Same check for each of the other edited skill pairs (`verify-changes`, `investigate`, `fix-issues`, `update-zskills`). Per-edit verification — do not wait until the end of Phase 2.
- [ ] `bash tests/run-all.sh` passes with all green. (No existing test asserts on SKILL.md prose text; count should be unchanged from Phase 1.)
- [ ] Manual smoke: pick the updated recipe from `skills/verify-changes/SKILL.md:208`, copy-paste into a shell run from repo root, confirm `.test-results.txt` lands at `/tmp/zskills-tests/zskills/.test-results.txt` and NOT at `./test-results.txt`.

### Dependencies

Phase 1 (idiom must exist in CLAUDE.md and CLAUDE_TEMPLATE.md before skills reference it).

## Phase 3 — Update hook message, land-phase.sh /tmp cleanup, and regression test

### Goal

Synchronize the hook error message with the new idiom, extend `scripts/land-phase.sh` to remove `/tmp/zskills-tests/<worktree-basename>/` on successful landing, and extend the existing regression test in `tests/test-hooks.sh` to cover the new cleanup.

### Work Items

- [ ] **`hooks/block-unsafe-project.sh.template:115`** — update the `block_with_reason` message. Current:
  ```
  Don't pipe test output -- it loses failure details. Instead: ${FULL_TEST_CMD:-npm run test:all} > .test-results.txt 2>&1 then read the file. To inspect results, grep the captured file.
  ```
  New:
  ```
  Don't pipe test output -- it loses failure details. Instead: TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; ${FULL_TEST_CMD:-npm run test:all} > "$TEST_OUT/.test-results.txt" 2>&1 then read "$TEST_OUT/.test-results.txt" to inspect failures.
  ```

- [ ] **`.claude/hooks/block-unsafe-project.sh:115`** — apply the exact same edit. (Round 1 DA3 doubted this file's existence; `ls -la .claude/hooks/` confirmed it exists at 22712 bytes. DA finding was wrong, no additional action needed — just edit both.)

- [ ] **`scripts/land-phase.sh`** — extend cleanup:
  - Leave the `EPHEMERAL_FILES` array at line 61 unchanged (see Design note below).
  - After the EPHEMERAL_FILES removal loop (around line 78, immediately before the `.landed` removal block at line 80), insert:
    ```bash
    # Remove the per-worktree /tmp test-output directory, if it exists.
    # Non-fatal: /tmp housekeeping must never block worktree cleanup.
    TEST_OUT_DIR="/tmp/zskills-tests/$(basename "$WORKTREE_PATH")"
    if [ -d "$TEST_OUT_DIR" ]; then
      if rm -rf "$TEST_OUT_DIR"; then
        :
      else
        echo "WARNING: failed to remove $TEST_OUT_DIR (non-fatal; will be cleaned at next reboot or manually)"
      fi
    fi
    ```

- [ ] **`tests/test-hooks.sh`** — extend the existing land-phase cleanup regression (currently lines 935-962). The existing test creates `$LAND_TMPDIR`, populates artifacts, invokes `land-phase.sh`, checks artifacts are gone. Extend as follows:
  - Before invoking `land-phase.sh`, also create `/tmp/zskills-tests/$(basename "$LAND_TMPDIR")/` and put a dummy file in it:
    ```bash
    TMP_TEST_OUT="/tmp/zskills-tests/$(basename "$LAND_TMPDIR")"
    mkdir -p "$TMP_TEST_OUT"
    printf 'dummy\n' > "$TMP_TEST_OUT/.test-results.txt"
    ```
  - After invoking `land-phase.sh`, add a check:
    ```bash
    TEST_OUT_GONE=0
    [ ! -d "$TMP_TEST_OUT" ] && TEST_OUT_GONE=1
    ```
  - Extend the existing pass condition. Current:
    ```bash
    if [ "$ARTIFACTS_GONE" -eq 4 ] && [ "$MARKER_PRESERVED" -eq 1 ]; then
    ```
    becomes:
    ```bash
    if [ "$ARTIFACTS_GONE" -eq 4 ] && [ "$MARKER_PRESERVED" -eq 1 ] && [ "$TEST_OUT_GONE" -eq 1 ]; then
    ```
  - Update the `pass` message at line 959 to mention the new assertion:
    ```
    pass "land-phase.sh: removes worktree artifacts AND /tmp test-out dir, preserves .landed on failure"
    ```
  - Update the `fail` message to include the new counter:
    ```
    fail "land-phase.sh: artifacts cleanup — gone=$ARTIFACTS_GONE/4, marker=$MARKER_PRESERVED, tmp_out_gone=$TEST_OUT_GONE, output: $LAND_OUTPUT"
    ```
  - Add symmetric cleanup of the /tmp test-out dir regardless of pass/fail (defensive — don't leave orphan dirs across runs). After the `rm -rf "$LAND_TMPDIR"` line (currently line 957), add:
    ```bash
    rm -rf "$TMP_TEST_OUT"
    ```

  This is ONE compound `pass` call (same shape as the existing test). The total pass-call count is UNCHANGED — Round 1 R3+DA6 caught that the original plan's "+2 tests → 237" was wrong. We now add zero new `pass` calls; we extend the existing one.

- [ ] **Search `tests/test-hooks.sh` for hook message assertions.** Run `grep -n 'test-results' tests/test-hooks.sh`. Each match is either the land-phase regression (lines 942-943, 951-952, kept as-is — they validate the EPHEMERAL_FILES canary) or a hook-message assertion that must be updated to match the new error string. Update any hook-message assertion found.

### Design & Constraints

- **Why retain the `EPHEMERAL_FILES` array and canary behaviour.** `scripts/land-phase.sh:62-78` is a **contract-violation canary**, not defense-in-depth: if any of the four files is git-tracked it exits 1 with `ERROR: $f is git-tracked`. Post-refactor, the test-output files should never appear in the worktree at all, so the canary is dormant. We keep it because:
  1. An agent running an old SKILL.md (not yet synced) might still write to the worktree — the canary catches this and blocks landing.
  2. The existing regression test at `tests/test-hooks.sh:935-962` exercises this canary; removing the canary would break the test for no gain.
  3. The canary is ~20 lines of code with zero runtime cost when files are absent.
- **`/tmp` cleanup is advisory.** If `rm -rf "$TEST_OUT_DIR"` fails (permissions, external race), we emit a warning and proceed. Worktree removal must not block on `/tmp` housekeeping.
- **Concurrency note — parallel basename collision.** Two worktrees at different paths with identical basenames (e.g., `/tmp/zskills-pr-foo` removed, `/work/zskills-pr-foo` created milliseconds later) could collide on `/tmp/zskills-tests/zskills-pr-foo/`. In practice worktree paths are generated with unique plan slugs (`zskills-pr-<plan-slug>`), so this is extraordinarily narrow. We accept the risk rather than add mtime-based safeguards, which would add complexity for a scenario that does not occur in the normal pipeline flow.
- **`set -e` compatibility.** `scripts/land-phase.sh` does not use `set -e` today (verify before editing); the inserted `rm -rf` with explicit `if` branching is safe either way.
- **Hook detection is path-agnostic.** The block logic in `hooks/block-unsafe-project.sh.template` matches on the shape of the piped test command (e.g., `npm test | grep` or similar), not on the filename `.test-results.txt`. We update only the error message string; detection logic is untouched.

### Acceptance Criteria

- [ ] `grep -n '\.test-results\.txt' hooks/block-unsafe-project.sh.template` returns only matches inside the new error-message string.
- [ ] `diff -u hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh` — no diff on line 115 (both copies have the same new message).
- [ ] Manual hook smoke: construct a minimal PreToolUse JSON with a piped test command, run the hook, confirm it blocks with the new message mentioning `TEST_OUT`. Exact command:
  ```bash
  echo '{"tool_name":"Bash","tool_input":{"command":"npm test | tail"}}' | bash .claude/hooks/block-unsafe-project.sh
  ```
  Expect exit code != 0 and stderr containing `TEST_OUT=`.
- [ ] `bash tests/run-all.sh` passes with the same pass count as before Phase 3 (no new `pass` calls added; one existing `pass` extended).
- [ ] Manual land-phase smoke:
  ```bash
  SMOKE=$(mktemp -d)
  printf 'status: landed\ndate: 2026-01-01\n' > "$SMOKE/.landed"
  mkdir -p "/tmp/zskills-tests/$(basename "$SMOKE")"
  printf 'dummy\n' > "/tmp/zskills-tests/$(basename "$SMOKE")/.test-results.txt"
  bash scripts/land-phase.sh "$SMOKE" 2>&1 || true
  [ -d "/tmp/zskills-tests/$(basename "$SMOKE")" ] && echo FAIL || echo PASS
  rm -rf "$SMOKE"
  ```
  Expect `PASS`.

### Dependencies

Phase 1 provides the idiom referenced by the hook's error message. Phase 2 is independent of Phase 3; both must complete before Phase 4 removes the wildcard `.gitignore`.

## Phase 4 — Pre-gate clean-tree check, remove wildcard .gitignore, gitignore .claude/logs

### Goal

Verify the working tree is clean of test-output leaks BEFORE removing the wildcard `.gitignore` safety net. Then remove the 412b097 wildcards, add `.claude/logs/` to `.gitignore`, and run the final acceptance grep.

### Work Items

- [ ] **Pre-gate clean-tree check** (Round 1 DA8 fix) — BEFORE editing `.gitignore`, run the full test suite and scan the filesystem directly for any `.test-*.txt` / `.*-results.txt` / `.*-diff.txt` leak. IMPORTANT: do NOT use `git status` here — the 412b097 wildcards still mask leaks from git status at this point. Use `find` with `-prune`:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  TEST_RC=$?
  # Leaks check: filesystem scan, bypasses .gitignore
  LEAKS=$(find . \( -name '.git' -o -name 'node_modules' \) -prune -o -type f \( -name '.test-*.txt' -o -name '.*-results*.txt' -o -name '.*-diff*.txt' \) -print 2>/dev/null || true)
  if [ -n "$LEAKS" ]; then
    echo "ABORT: test-output files leaked into working tree:"
    echo "$LEAKS"
    echo "Phase 2/3 missed a callsite. Do NOT remove wildcard gitignore yet."
    exit 1
  fi
  [ "$TEST_RC" -eq 0 ] || { echo "ABORT: tests failed rc=$TEST_RC"; exit 1; }
  ```
  If the pre-gate aborts, fix Phase 2 or Phase 3 before proceeding. (Note: the Design & Constraints section below explains why `find` rather than `git status`.)

- [ ] **Edit `.gitignore`** — remove lines 7-15 (the 412b097 additions). Delete the block:
  ```
  # Ephemeral agent artifacts (test outputs, diff captures, lifecycle markers).
  # Wildcards catch current + future variants so we don't have to whack-a-mole
  # one filename at a time. Real fix is to route test outputs to /tmp — see
  # plans/EPHEMERAL_TMP_MIGRATION.md (if/when drafted).
  .test-*.txt
  .*-results.txt
  .*-results-*.txt
  .*-diff.txt
  .*-diff-*.txt
  ```
  Keep the remaining entries (`.worktreepurpose`, `.landed`, `.claude/scheduled_tasks.json`, `.claude/scheduled_tasks.lock`).

- [ ] **Add `.claude/logs/` to `.gitignore`.** Place it in the same group as `.claude/scheduled_tasks.*` (the `.claude/` ephemera group). After `.claude/scheduled_tasks.lock` add:
  ```
  .claude/logs/
  ```
  Use the trailing slash to match the directory form explicitly.

- [ ] **Final acceptance grep** — this is the user's stated acceptance criterion. Run:
  ```bash
  grep -rEn '\.test-(results|baseline|output).*\.txt' skills/ CLAUDE.md .claude/skills/
  ```
  Every hit must be either:
  - Inside the new idiom (`"$TEST_OUT/.test-results.txt"` / `"$TEST_OUT/.test-baseline.txt"`)
  - Inside the hygiene list prose at `skills/run-plan/SKILL.md:608-609` (and mirror) — intentional per-Phase-2
  - Inside the fix-issues filter pattern at `skills/fix-issues/SKILL.md:1074` (and mirror) — intentional per-Phase-2

  A human reviewer should be able to say "each hit is intentional" for every line in the grep output. If any hit is an unintentional old-pattern writer, it is a bug introduced by a missed callsite in Phase 2 — fix before committing Phase 4.

- [ ] **Full test suite** — run `bash tests/run-all.sh`, confirm all pass.

- [ ] **Post-edit clean-tree confirmation**:
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  git status -s | grep -E '\.test-' && echo FAIL || echo PASS
  ```
  Expect `PASS`. (This is identical in spirit to the pre-gate but run AFTER `.gitignore` is edited to be sure nothing regressed.)

- [ ] **Verify `.claude/logs/` ignore rule works**:
  ```bash
  mkdir -p .claude/logs
  touch .claude/logs/dummy-log.md
  git check-ignore -v .claude/logs/dummy-log.md
  ```
  Expect the check-ignore to report `.gitignore:<N>:.claude/logs/	.claude/logs/dummy-log.md`. Remove the dummy: `rm .claude/logs/dummy-log.md` (keep the directory if other phases created it, else `rmdir .claude/logs`).

### Design & Constraints

- **Ordering is strict.** The pre-gate check MUST run before `.gitignore` is edited. If any Phase-2 callsite was missed, the wildcards still hide the leak from `git status` — so the pre-gate CANNOT rely on `git status`. The pre-gate must bypass git-ignore entirely, which is why the implementation uses `find` to scan the filesystem directly (next bullet).

- **Pre-gate implementation — scan filesystem, not `git status`.** The pre-gate script is specified in the Work Items section. Key design choices: `find` with `-prune` of `.git`/`node_modules` rather than `-maxdepth N`, so the check covers leaks at any depth (not just depth ≤ 2). `find` sees files regardless of git-ignore rules, which is what we need while the wildcards are still in place.

- **Why `.claude/logs/` with trailing slash.** Git's ignore rules treat `.claude/logs/` (directory-only) and `.claude/logs` (file or directory) differently. The former is semantically what we want — ignore the contents of the `logs` subdirectory. Use the trailing slash.
- **Scope of the acceptance grep.** Per the user's prompt: `skills/ CLAUDE.md .claude/skills/`. Do NOT expand to `plans/` — those are historical.
- **Upgrade-path for downstream projects.** Projects that already installed zskills will have the OLD `CLAUDE.md` in their tree until they run `/update-zskills` (which will pull the new `CLAUDE_TEMPLATE.md`). Until then, their agents will still write to the working tree. That's not this plan's problem — downstream projects opt in to zskills updates on their own schedule. This plan's commit message / PR body should note the upgrade path as a one-liner to avoid surprise.
- **In-flight upgrade advisory.** A downstream project that runs `/update-zskills` while mid-pipeline (with uncommitted `.test-results.txt` in their working tree) will inherit the new `.gitignore` (no wildcards) and the files will newly appear in `git status`. The advisory in the PR body should note: "If upgrading with active worktrees, clear any `.test-*.txt`, `.*-results.txt`, `.*-diff.txt` files from your working tree before pulling the new `.gitignore`, or add them to `.git/info/exclude` locally until those pipelines land."
- **Known limitation — /tmp assumption.** This plan hardcodes `/tmp/zskills-tests/` as the output location. Downstream projects running in containerized CI or sandboxed runners that reject writes to `/tmp` will need to override. No override mechanism is in scope for this plan — that would require a config field + an extractor in `update-zskills`, which the plan explicitly deferred. If a downstream project hits this, they fork `CLAUDE.md` and the affected skill recipes and manage their own convention.

### Acceptance Criteria

- [ ] Pre-gate passes (amended version using `find`, not `git status`).
- [ ] `.gitignore` no longer contains any of the 412b097 wildcard patterns: `.test-*.txt`, `.*-results.txt`, `.*-results-*.txt`, `.*-diff.txt`, `.*-diff-*.txt`. Verified with `grep -E '\.test-\*\.txt|\.\*-results|\.\*-diff' .gitignore` returning no output.
- [ ] `.gitignore` contains `.claude/logs/` on its own line with trailing slash. Verified with `grep -n '^\.claude/logs/$' .gitignore`.
- [ ] The user's stated acceptance grep — `grep -rEn '\.test-(results|baseline|output).*\.txt' skills/ CLAUDE.md .claude/skills/` — returns only intentional hits (idiom references, hygiene prose, fix-issues filter).
- [ ] `bash tests/run-all.sh` passes, all green.
- [ ] `git check-ignore -v .claude/logs/anything.md` reports the rule matches.
- [ ] Post-edit clean-tree: running the full test suite leaves no `.test-*.txt` visible in `git status`.
- [ ] `git status -s` in the final state shows ONLY the files this plan touched, nothing else.

### Dependencies

Phases 1, 2, and 3 must all be complete before Phase 4. Phase 4 is the safety-net removal; it assumes no callsite is still writing to the working tree.

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (Reviewer + Devil's Advocate in rounds 1-2; single combined convergence reviewer in round 3).
**Convergence:** Converged at Round 3 — the round-3 reviewer found 1 MAJOR finding (an internal contradiction between a Phase 1 work-item and its acceptance criterion, introduced in round-2 refinement), which was fixed in place. No substantive issues remain.
**Remaining concerns:** None blocking. Three minor quality notes that did not merit fixes: (a) the hook error message is now ~15% longer than the previous maximum in that file — still readable, no hard length limit exists; (b) in-flight downstream upgrades may see newly-visible test-output files in `git status` — documented as advisory in Phase 4 Design & Constraints; (c) containerized runners rejecting `/tmp` writes are unsupported by this plan — documented as a known limitation in Phase 4 Design & Constraints.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 11 (1 critical, 2 major, 5 minor, 3 nit) | 10 (1 critical, 3 major, 4 minor, 2 nit) | 20/21 (1 DA finding not reproduced — `.claude/hooks/block-unsafe-project.sh` actually exists; claim rejected with evidence) |
| 2     | 8 (0 critical, 3 major, 3 minor, 2 nit)  | 10 (0 critical, 3 major, 4 minor, 3 nit) | 15/18 actionable (3 no-action: placement OK, message length nit, count-framing nit) |
| 3     | 1 combined reviewer — 1 major finding    | (merged)                   | 1/1 — Phase 1 AC / Work Item contradiction fixed; duplicate pre-gate block in Phase 4 Design collapsed |
