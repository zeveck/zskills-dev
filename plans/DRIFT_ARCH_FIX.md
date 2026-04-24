---
title: Drift-Arch Fix — Runtime Config Read + Drift-Warn
created: 2026-04-23
status: complete
completed: 2026-04-24
---

# Plan: Drift-Arch Fix

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Fix a systemic drift-bug class in zskills: source templates (`hooks/*.template`, `scripts/port.sh`, `scripts/test-all.sh`, `CLAUDE_TEMPLATE.md`) contain `{{PLACEHOLDER}}` tokens that get filled at `/update-zskills` install time from `.claude/zskills-config.json`. After install, the rendered artifacts are **frozen snapshots** — post-install config edits go stale silently with no runtime re-read.

The bug that surfaced this: `.claude/hooks/block-unsafe-project.sh` lines 225-226 hardcode `UNIT_TEST_CMD`/`FULL_TEST_CMD` to `"bash tests/test-hooks.sh"` (314-test subset) while config declares `"bash tests/run-all.sh"` (733-test full suite). Pre-commit, pre-cherry-pick, and pipe-output gates all validated the wrong command. Introduced in `a9ad570` (Apr 18) when an agent hand-filled placeholders with stale values instead of running `/update-zskills`.

Two-track fix:

- **CODE consumers** (hooks, helper scripts) read `.claude/zskills-config.json` at runtime via bash regex — same idiom already used by `is_main_protected()` in the same hook (`a874492`, Apr 13) and by `scripts/apply-preset.sh`.
- **TEXT consumers** (CLAUDE.md, not executed) keep render-time fill but gain a drift-warn mechanism: a PostToolUse hook fires on edits to `.claude/zskills-config.json`, warning that CLAUDE.md may be stale and suggesting `/update-zskills --rerender` (new subcommand that regenerates the template-managed portion of CLAUDE.md while preserving user content).

Ship-blocker for 2026.04.1: yes. Shipping now propagates the render-time-snapshot architecture to every downstream `/update-zskills` consumer.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Migrate CODE consumers to runtime config read | ✅ Done | `3b3fc88` | 5 files; +14 tests; 733→747 |
| 2 — Update /update-zskills: drop migrated fills, add --rerender, fix settings.json clobber | ✅ Done | `8ce91de` | Step C agent-driven merge + Step D --rerender + 48 new test assertions; 747→801 |
| 3 — Add PostToolUse drift-warn hook + wire settings.json | ✅ Done | `e3e6b3c` | New hook + settings.json wiring + install-integrity note; +5 tests; 801→806 |
| 4 — Move zskills-managed content to `.claude/rules/zskills/managed.md` (supersedes Phase 2's Step D) | ✅ Done | `2cac108` | Namespaced subdir + simple rewrite + auto-migration + drift-warn path update; 806→815 |

## Phase 1 — Migrate CODE consumers to runtime config read

### Goal

Replace `{{PLACEHOLDER}}` install-time fills with runtime reads of `.claude/zskills-config.json` in all executed code paths. Drift becomes architecturally impossible for CODE consumers.

### Work Items

- [ ] 1.1 — Edit `hooks/block-unsafe-project.sh.template`:
  - **Replace lines 225-226 in place** with the runtime config-read block (see Design & Constraints). The block initializes `UNIT_TEST_CMD`, `FULL_TEST_CMD`, and `UI_FILE_PATTERNS`.
  - **Delete line 310** (the `UI_FILE_PATTERNS="{{UI_FILE_PATTERNS}}"` assignment) since it's now initialized by the block at the top. Keep the surrounding UI-file-detection logic intact; it will operate on the var set earlier.
  - **Add an explicit empty-pattern guard** immediately before the pipe-check loop (current lines 245-255): if both `UNIT_TEST_CMD` and `FULL_TEST_CMD` are empty, skip the pipe check entirely. See Design & Constraints for the guard code. Without this guard, the existing `TEST_PIPE_PATTERN="(${ESCAPED_UNIT}|${ESCAPED_FULL})"` becomes `(|)` which matches the empty string and blocks every piped command.
  - **Remove the placeholder-detection branch** (current lines 229-231) for the migrated vars. Those vars are now initialized to empty string, never `{{...}}`, so the branch is dead code. Similarly remove the placeholder branches in the commit-gate (lines 269-289) and cherry-pick-gate (lines 427-445) that check `FULL_TEST_CHECK == *'{{'*`.

- [ ] 1.2 — Mirror the template change into `.claude/hooks/block-unsafe-project.sh`. Byte-identical to the source template.

- [ ] 1.3 — Edit `scripts/port.sh`:
  - Remove `{{MAIN_REPO_PATH}}` from line 13 and line 25. Replace with a runtime config read of `dev_server.main_repo_path` at the top of the script.
  - Line 4's comment updated to reference runtime-read rather than install-fill.

- [ ] 1.4 — Edit `scripts/test-all.sh`:
  - Replace `{{UNIT_TEST_CMD}}` (line 15) with runtime config read of `testing.unit_cmd`.
  - Replace `{{MAIN_REPO_PATH}}` (line 49) with runtime config read of `dev_server.main_repo_path`.
  - **Leave** `{{E2E_TEST_CMD}}` (line 16) and `{{BUILD_TEST_CMD}}` (line 17) as placeholders — these have no config field in the current schema; they are install-filled by `/update-zskills` Step C. Add a comment above them: `# E2E_TEST_CMD / BUILD_TEST_CMD have no config source; install-filled by /update-zskills. See plan DRIFT_ARCH_FIX.md Out-of-Scope.`

- [ ] 1.5 — Add tests to `tests/test-hooks.sh` under a new section `=== Runtime config read ===`. Each test uses a temp fixture dir, writes a synthetic `.claude/zskills-config.json`, and invokes the hook with `REPO_ROOT=<fixture>` (env override already supported; see `is_main_protected`'s repo-root resolution). Test cases:
  - `full_cmd` read honored: fixture config `{"testing": {"full_cmd": "FIXTURE_FULL_CMD"}}`, synthesize `git commit` stdin with transcript containing `FIXTURE_FULL_CMD`; assert hook allows (rc=0, no deny).
  - `full_cmd` read honored: same fixture but transcript does NOT contain `FIXTURE_FULL_CMD`; assert hook blocks.
  - `unit_cmd` read honored: fixture with `{"testing": {"unit_cmd": "FIXTURE_UNIT"}}`, `Bash` command `FIXTURE_UNIT | head`; assert pipe-block fires.
  - `ui.file_patterns` read honored: fixture with `{"ui": {"file_patterns": "src/ui/"}}`; verify the downstream UI-touch detection uses `src/ui/`.
  - Fallback: no config file → both vars empty → empty-pattern guard kicks in → pipe check does NOT fire on unrelated piped commands (regression for the empty-regex bug).
  - Subdir invocation: fixture has config at root but cwd is `$FIXTURE/src/`; hook still resolves config correctly via `--show-toplevel`.
  - Worktree invocation: fixture is a `git worktree add` from a main repo with config at root; cwd is the worktree path; hook still resolves config correctly (worktree checkout has its own copy of `.claude/zskills-config.json` because the file is git-tracked).

- [ ] 1.6 — Add a drift-regression test asserting both deny-list and allow-list for placeholders in the installed hook and scripts:
  ```bash
  # Deny-list: migrated placeholders must be absent
  for tok in '{{UNIT_TEST_CMD}}' '{{FULL_TEST_CMD}}' '{{UI_FILE_PATTERNS}}' '{{MAIN_REPO_PATH}}'; do
    grep -Fq "$tok" .claude/hooks/block-unsafe-project.sh scripts/port.sh scripts/test-all.sh \
      && fail "migrated placeholder $tok still present"
  done
  # Allow-list: install-time placeholders must remain in test-all.sh
  for tok in '{{E2E_TEST_CMD}}' '{{BUILD_TEST_CMD}}'; do
    grep -Fq "$tok" scripts/test-all.sh || fail "install-time placeholder $tok missing"
  done
  ```

### Design & Constraints

**Canonical runtime-read idiom** (place at the top of each consumer, after shebang/comments, before any var that depends on it). Uses bash regex only (`feedback_no_jq_in_skills`):

```bash
# ─── Runtime config read (eliminates install-time drift) ───
# Config location: .claude/zskills-config.json in the checked-out tree.
# --show-toplevel matches the existing is_main_protected() pattern at
# line 146; in a worktree, this returns the worktree root, which is
# correct — the config is git-tracked, so each worktree reads its own
# branch-current version.
_ZSK_REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_ZSK_CFG="$_ZSK_REPO_ROOT/.claude/zskills-config.json"
UNIT_TEST_CMD=""
FULL_TEST_CMD=""
UI_FILE_PATTERNS=""
if [ -f "$_ZSK_CFG" ]; then
  _ZSK_CFG_BODY=$(cat "$_ZSK_CFG" 2>/dev/null) || _ZSK_CFG_BODY=""
  if [[ "$_ZSK_CFG_BODY" =~ \"unit_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UNIT_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  if [[ "$_ZSK_CFG_BODY" =~ \"full_cmd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    FULL_TEST_CMD="${BASH_REMATCH[1]}"
  fi
  # ui.file_patterns: scope via enclosing "ui" object to disambiguate
  # from testing.file_patterns (array, doesn't match the string regex
  # anyway, but prefix scoping is defensive against future schema change).
  if [[ "$_ZSK_CFG_BODY" =~ \"ui\"[[:space:]]*:[[:space:]]*\{[^}]*\"file_patterns\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    UI_FILE_PATTERNS="${BASH_REMATCH[1]}"
  fi
  unset _ZSK_CFG_BODY
fi
unset _ZSK_REPO_ROOT _ZSK_CFG
```

**Empty-pattern guard + expanded regex escape** (Phase 1.1, replaces/wraps current lines 245-255). The existing code escapes only `.` and space; addresses R2-DA "regex escaping incomplete" by covering all bash-regex metacharacters that could appear in a user's configured test command:

```bash
# Escape every bash-regex metacharacter that might appear in a config
# test-command string (parens, brackets, pipe, asterisk, plus, etc.).
# Then re-space spaces to [[:space:]]+ so "bash  tests/run-all.sh"
# (multiple spaces) still matches.
_zsk_regex_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//\(/\\(}"
  s="${s//\)/\\)}"
  s="${s//[/\\[}"
  s="${s//]/\\]}"
  s="${s//|/\\|}"
  s="${s//\*/\\*}"
  s="${s//+/\\+}"
  s="${s//?/\\?}"
  s="${s//\$/\\\$}"
  s="${s//^/\\^}"
  s="${s//\{/\\{}"
  s="${s//\}/\\}}"
  s="${s// /[[:space:]]+}"
  printf '%s' "$s"
}

# Guard: without both vars set, TEST_PIPE_PATTERN="(|)" matches empty
# string and blocks every piped command. Skip the pipe check entirely
# if both are empty (config missing or test fields unset).
if [ -n "$UNIT_TEST_CMD" ] || [ -n "$FULL_TEST_CMD" ]; then
  ESCAPED_UNIT=""
  ESCAPED_FULL=""
  [ -n "$UNIT_TEST_CMD" ] && ESCAPED_UNIT="$(_zsk_regex_escape "$UNIT_TEST_CMD")"
  [ -n "$FULL_TEST_CMD" ] && ESCAPED_FULL="$(_zsk_regex_escape "$FULL_TEST_CMD")"
  # Only alternate non-empty vars to avoid "(|cmd)" degenerate case.
  if [ -n "$ESCAPED_UNIT" ] && [ -n "$ESCAPED_FULL" ]; then
    TEST_PIPE_PATTERN="(${ESCAPED_UNIT}|${ESCAPED_FULL})"
  elif [ -n "$ESCAPED_UNIT" ]; then
    TEST_PIPE_PATTERN="${ESCAPED_UNIT}"
  else
    TEST_PIPE_PATTERN="${ESCAPED_FULL}"
  fi
  # ... existing segment-split + pipe-check loop (unchanged) ...
fi
```

**Fallback behavior** (explicit per DA-m9): if config is missing or fields are unset/empty, all vars default to empty string. The empty-pattern guard skips the pipe check. Commit and cherry-pick transcript gates search for an empty string in transcript (always matches; gate passes trivially). **This is a safe degrade** — the gates' primary purpose is catching "tests weren't run"; if the project has no tests configured, there's nothing to check. Projects with tests should configure `testing.full_cmd`.

**Dead code cleanup** (per DA-M5): after migration the `{{` placeholder-detection branches at lines 229-231, 269-289, 427-445 never execute (vars are always "", never "{{..}}"). Phase 1.1 removes these branches. This shrinks the hook by ~40 lines and removes maintenance burden.

**No jq**. Bash regex only.

**Field-name scoping for UI_FILE_PATTERNS** (per DA-M7): the scoped regex (`"ui"...{...file_patterns...}`) is defensive. Constrain `testing.file_patterns` to remain an array in `.claude/zskills-config.schema.json` (if not already). Document this as a schema invariant in Phase 2 docs update.

**Installed-copy sync**. Source at `hooks/block-unsafe-project.sh.template`, installed at `.claude/hooks/block-unsafe-project.sh`. No automatic sync; Phase 1.2 writes both explicitly.

### Acceptance Criteria

- [ ] Drift-regression grep (WI 1.6) passes both deny-list and allow-list assertions.
- [ ] All six test cases in WI 1.5 pass.
- [ ] `bash tests/run-all.sh` passes (existing 733 + new tests from 1.5/1.6).
- [ ] Automated smoke test (replaces the round-1 manual "observe"): a test writes a synthetic fixture config with `"testing.full_cmd": "FIXTURE_X"` to a temp repo, synthesizes a `git commit` tool event, captures the hook's stderr + exit code, and asserts (a) block message references `FIXTURE_X` verbatim and (b) no restart/reinstall was performed between config write and hook invocation. Evidence that runtime-read works end-to-end.
- [ ] `.claude/hooks/block-unsafe-project.sh` no longer contains the `if [[ "$FULL_TEST_CHECK" == *'{{'* ]]` branches (grep returns 0 for `'{{'` at those gate locations).

### Dependencies

None. First phase.

## Phase 2 — Update /update-zskills: drop migrated fills, add --rerender, fix settings.json clobber

### Goal

Align the installer with the new runtime-read architecture, provide a single-command way to refresh CLAUDE.md (the one remaining render-time-fill artifact) when config changes, and close a pre-existing bug where Step C full-overwrites `.claude/settings.json`'s `hooks` object — clobbering any user-added `PreToolUse` entries on every install.

### Work Items

- [ ] 2.1 — Edit `skills/update-zskills/SKILL.md` Step C (hook gaps, lines 618-642): remove placeholder-fill instructions for `{{UNIT_TEST_CMD}}`, `{{FULL_TEST_CMD}}`, `{{UI_FILE_PATTERNS}}` in `block-unsafe-project.sh` and `{{MAIN_REPO_PATH}}`, `{{UNIT_TEST_CMD}}` in `scripts/port.sh` / `scripts/test-all.sh`. Add a note: `# Note: hooks and helper scripts read testing.*, ui.file_patterns, and dev_server.main_repo_path from .claude/zskills-config.json at runtime. No install-time fill needed. Only copy the source template.` Keep the `{{E2E_TEST_CMD}}` / `{{BUILD_TEST_CMD}}` fill logic (no config source).
- [ ] 2.2 — Edit the placeholder-mapping table (lines 320-321): remove the migrated rows; add a one-line note `Runtime-read fields (not install-filled): testing.unit_cmd, testing.full_cmd, ui.file_patterns, dev_server.main_repo_path.`
- [ ] 2.3 — Add a `### Step D — --rerender` section to `skills/update-zskills/SKILL.md`. Trigger: user runs `/update-zskills --rerender`. Behavior spec + boundary-detection algorithm in Design & Constraints below.
- [ ] 2.4 — Add a test under `tests/test-skill-conformance.sh` (or new `tests/test-update-zskills-rerender.sh`) exercising --rerender. Test cases:
  - Happy path: stale CLAUDE.md + updated config → new CLAUDE.md contains current config values.
  - Preservation: user added content below `## Agent Rules` → content below heading preserved verbatim.
  - Conflict: user edited content above `## Agent Rules` (e.g., inserted a custom paragraph) → new content written to `CLAUDE.md.new`, `CLAUDE.md` untouched, rc=2 with a specific prompt on stderr.
  - Missing file: no CLAUDE.md exists → rc=1 with error "no existing CLAUDE.md; run `/update-zskills` (without --rerender) for initial install".
  - Idempotency: run --rerender twice in a row → second run is a no-op (rc=0, CLAUDE.md unchanged).

- [ ] 2.5 — **Rewrite Step C settings.json handling as an agent-driven surgical merge** (replaces the current full-overwrite in `skills/update-zskills/SKILL.md` lines 658-692). Specifies that the agent (the one executing `/update-zskills`) uses `Read` + `Edit` tools — not a bash script and not `Write`-from-template — to merge zskills-owned hook entries into `.claude/settings.json` while preserving every other top-level key and every non-zskills-owned hook entry. Algorithm + canonical triples table in Design & Constraints. Aligns Step C with the house-style surgical-edit pattern already used in Step B (CLAUDE.md rules append, lines 608-616) and the `zskills-config.json` backfill (lines 224-234).

- [ ] 2.6 — Add a `Step C.9 — Hook renames` subsection to `skills/update-zskills/SKILL.md`. Contains an explicit `old_command → new_command` migration table (initially empty, with a comment explaining when and how to add rows). Step C.9 runs BEFORE the main merge loop of WI 2.5, so renames happen in place (single Edit replacing the old command string with the new one) rather than producing orphan entries. Migration rows are reviewed at code-review time when a hook rename ships. See Design & Constraints.

- [ ] 2.7 — Add tests under `tests/test-skill-conformance.sh` or a new `tests/test-update-zskills-stepc.sh` asserting the Step C merge contract (by inspecting the SKILL.md instructions, not by executing the skill — we can't execute a skill inside a shell test). Test cases (as structural assertions on SKILL.md):
  - Step C explicitly says "Read + Edit" not "Write the whole file".
  - Step C contains the canonical zskills-owned triples table (event, matcher, command) for all 4 hooks (3 PreToolUse + 1 PostToolUse).
  - Step C preserve rule is present ("never overwrite; never reorder top-level keys").
  - Step C mentions the preview-and-confirm step (mirrors Step B convention).
  - Step C.9 rename table exists and is initially empty.
  Plus a separate integration test: write a synthetic settings.json fixture with a user-added custom Bash hook, write a doc asserting the Step C spec would preserve that hook (doc-check, not execution).

### Design & Constraints

**--rerender scope**: regenerates CLAUDE.md only. Hooks and helper scripts are runtime-read; they auto-reflect config. No touching of settings.json, skills, or source templates.

**Boundary-detection algorithm** (addresses DA-C4 / R-C1; simplified per R2 to eliminate the "normalize by substituting prior-known values" hand-waving):

1. Read existing CLAUDE.md. Locate `## Agent Rules` via `grep -n '^## Agent Rules[[:space:]]*$' CLAUDE.md | head -1`. Tolerant of trailing whitespace, strict on leading `##` and surrounding blank lines. If not found → exit 2 with error: "CLAUDE.md missing `## Agent Rules` demarcation; cannot rerender safely. Add the heading or re-run /update-zskills (without --rerender) for initial install."
2. Split existing CLAUDE.md on the heading line: `existing_above` (lines 1 .. heading_line-1), `existing_below` (heading_line .. end).
3. Render CLAUDE_TEMPLATE.md against current `.claude/zskills-config.json`: for each placeholder (`{{PROJECT_NAME}}`, `{{DEV_SERVER_CMD}}`, ...), substitute the current config value (per Step B's existing fill logic, unchanged). Locate the `## Agent Rules` heading in the rendered output; extract `fresh_above`.
4. **Byte-compare** `existing_above` to `fresh_above` (after right-trimming trailing whitespace on each line, to tolerate editor-induced whitespace churn). No "normalize by substituting" — if they differ, the differences are either user edits OR config-change-since-last-render. Both cases mean the user should review before overwriting.
   - **Identical**: write `fresh_above` + `existing_below` to `CLAUDE.md`. Exit 0. (If bytes unchanged, skip the write entirely so file mtime stays stable — ensures idempotency.)
   - **Different**: write `fresh_above` + `existing_below` to `CLAUDE.md.new`. Do NOT overwrite `CLAUDE.md`. Print to stderr verbatim:
     ```
     CLAUDE.md differs above '## Agent Rules' (user edits, config drift, or both).
     New rendered content written to CLAUDE.md.new. Review with:
         diff CLAUDE.md CLAUDE.md.new
     To accept the new version:  mv CLAUDE.md.new CLAUDE.md
     To discard it:              rm CLAUDE.md.new
     ```
     Exit 2.

**Prompt text in conflict case**: exactly the diff-command + merge-instructions shown above — no interactive prompt (respects headless `/update-zskills` invocations).

**Idempotency**: after a clean rerender, re-running --rerender sees `above` region already matches fresh template → no diff → writes unchanged content → effectively no-op. Acceptance criteria asserts `stat -c%Y CLAUDE.md` unchanged across second run (or content hash identical).

**Missing CLAUDE.md**: exit 1 with error. Do not create one silently.

**Backward compatibility**: removing Step C fills for migrated keys is safe — older templates still on disk that have `{{UNIT_TEST_CMD}}` un-filled will, at runtime, fall through to the empty-string fallback. Downstream projects running `/update-zskills` (post-upgrade) simply stop filling those placeholders, which is what we want.

**Step C settings.json merge contract (agent-driven, not scripted)**. `/update-zskills` is a skill always executed by a Claude Code agent session — there is no script-mode invocation. Step C therefore instructs the agent to perform the merge using `Read` and `Edit` tools directly, reasoning about JSON structure natively. No bash-JSON-splice, no jq, no full-file `Write`.

**Canonical zskills-owned triples table** (single source of truth in the SKILL.md):

```
Event        Matcher  Command literal
-----        -------  ---------------
PreToolUse   Bash     bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-generic.sh"
PreToolUse   Bash     bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-unsafe-project.sh"
PreToolUse   Agent    bash "$CLAUDE_PROJECT_DIR/.claude/hooks/block-agents.sh"
PostToolUse  Edit     bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"
PostToolUse  Write    bash "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh"
```

All 5 rows use `"timeout": 5` and `"type": "command"`. The table is the definition of "zskills-owned"; anything not in it is foreign and preserved untouched.

**Step C algorithm**:

1. **Read** `.claude/settings.json`. If the file does not exist, `Write` a minimal file containing only the zskills `hooks` block populated from the table. Stop — nothing to preserve on a fresh install.
2. If the top-level `hooks` key is absent, `Edit` to insert a `"hooks": { "PreToolUse": [], "PostToolUse": [] }` skeleton adjacent to the existing top-level keys. Do not touch `permissions`, `env`, `statusLine`, `model`, or any other existing top-level key.
3. First, **run Step C.9 renames** (see WI 2.6): for each `old_command → new_command` row in the migration table, search the entire `hooks.PreToolUse` and `hooks.PostToolUse` arrays for an entry whose `command` equals `old_command`. If found, `Edit` to replace the exact `old_command` string with `new_command` in place. The surrounding structure (matcher, timeout, siblings) is preserved.
4. For each `(event, matcher, command)` triple in the canonical table:
   a. Search the ENTIRE `hooks.<event>` array (all matcher blocks) for an object whose `hooks[*].command` equals `command` exactly. If found anywhere — even under a different matcher — treat as "already present" and skip (do not duplicate).
   b. Otherwise, locate the matcher block whose `matcher` field equals the triple's matcher. If present, `Edit` to append the zskills hook object to that matcher block's `hooks` array. Do not touch sibling hook objects (user-added customizations in the same matcher survive).
   c. If no matcher block with that matcher exists, `Edit` to append a new `{ "matcher": "<matcher>", "hooks": [ <zskills entry> ] }` object to `hooks.<event>`.
5. Never reorder top-level keys, never strip whitespace from untouched regions, never re-emit the file from a template, never remove entries not listed in the rename table (Step C.9) or already-present check (step 4a).
6. Before making any `Edit`, display a diff-style preview to the user ("+ add block-agents.sh under Agent matcher", "skip: block-unsafe-generic.sh already present", "rename: block-unsafe-project.sh → deny-unsafe.sh") and ASK for confirmation — mirrors the Step B CLAUDE.md convention (lines 608-616). On confirmation, perform the Edits; on rejection, report which entries were missing and exit without changes.
7. Report: "Step C: registered N hook entries, skipped M already present, renamed R, preserved F foreign entries."

**Why agent-driven, not scripted**. Three prior adversarial reviews of bash-splice approaches (append-if-missing, overwrite-if-stock, partition-by-ownership) all concluded the bash implementation is high-cost / high-risk for nested JSON arrays. The `Edit` tool's exact-string-matching + LLM reasoning about JSON structure makes the operation natural. Precedents in this same skill: Step B CLAUDE.md append (608-616), config backfill (224-234), `apply-preset.sh` line splice (854-858) — all surgical, all agent-driven, all preserve-by-default. Step C aligns with the house style.

**Step C.9 rename migration table** (initially empty):

```
# When a zskills release renames a hook file, add a row here:
# old_command: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<old-name>.sh"
# new_command: bash "$CLAUDE_PROJECT_DIR/.claude/hooks/<new-name>.sh"
# Committed in the same PR that ships the rename. Rows accumulate; the table
# is append-only. Step C.9 runs each row against every install; rows are
# idempotent (if old_command absent, the row is a no-op).
```

### Acceptance Criteria

- [ ] `skills/update-zskills/SKILL.md` Step C no longer references the four migrated placeholders for fill. Keeps `{{E2E_TEST_CMD}}` / `{{BUILD_TEST_CMD}}` fill logic.
- [ ] `skills/update-zskills/SKILL.md` gains a `### Step D — --rerender` section documenting trigger, boundary algorithm, exit codes (0 clean, 1 missing, 2 conflict), and user-facing stderr message verbatim.
- [ ] `skills/update-zskills/SKILL.md` Step C is rewritten to the agent-driven merge algorithm described above, including the canonical triples table, the explicit "Read + Edit, never Write whole file" rule, and the preview-and-confirm step.
- [ ] `skills/update-zskills/SKILL.md` gains a `### Step C.9 — Hook renames` subsection with an initially-empty migration table and the contribution instructions (add a row in the same PR that ships the rename).
- [ ] All 5 test cases in WI 2.4 pass (--rerender).
- [ ] All structural test cases in WI 2.7 pass (Step C / Step C.9 contract).
- [ ] `bash tests/run-all.sh` passes.

### Dependencies

Depends on Phase 1 (Step C knows these keys are no longer fill targets because consumers already read at runtime).

## Phase 3 — Add PostToolUse drift-warn hook + wire settings.json

### Goal

Warn the user when they edit `.claude/zskills-config.json` that CLAUDE.md may be stale. Non-blocking.

### Work Items

- [ ] 3.1 — Create `hooks/warn-config-drift.sh` (source template). Reads tool-event JSON from stdin; detects `tool_name` equal to `"Edit"` or `"Write"`; matches `tool_input.file_path` with a suffix check — the path ends with `.claude/zskills-config.json` (handles absolute, repo-relative, or cwd-relative paths). Emits a non-blocking warn on stderr. Always exits 0. See Design & Constraints for exact match idiom and warn text.

- [ ] 3.2 — Mirror to `.claude/hooks/warn-config-drift.sh` (installed copy, `chmod +x`).

- [ ] 3.3 — Edit `.claude/settings.json` (zskills repo): add the two PostToolUse entries (Edit + Write matchers) by executing the Step C merge algorithm from Phase 2 WI 2.5 against the current file. After landing Phase 2, this is a one-time invocation of the new agent-driven merge, not a standalone wiring spec. Preserves existing `PreToolUse` and all top-level keys.

- [ ] 3.4 — Add the two new PostToolUse triples (Edit + Write matcher pointing at `warn-config-drift.sh`) to Phase 2's canonical zskills-owned triples table. That's the only change to `skills/update-zskills/SKILL.md` Step C that Phase 3 contributes — everything else (install-integrity check for the hook file, the merge algorithm, preview-and-confirm) is already in Step C's spec from Phase 2.

- [ ] 3.5 — Add tests to `tests/test-hooks.sh` under new section `=== PostToolUse: config drift warn ===`:
  - Synthetic `Edit` event on `.claude/zskills-config.json` → stderr contains `CLAUDE.md` + `/update-zskills --rerender`; rc=0.
  - Synthetic `Edit` event on `.claude/zskills-config.json` via absolute path `/workspaces/zskills/.claude/zskills-config.json` → same warn (suffix matcher).
  - Synthetic `Edit` event on `package.json` → stderr empty; rc=0.
  - Synthetic `Write` event on `.claude/zskills-config.json` → same warn; rc=0.
  - Malformed stdin (not JSON) → rc=0, stderr empty.

### Design & Constraints

**Warn text** (stderr, verbatim):

> NOTE: You just edited `.claude/zskills-config.json`.
>
> - Hooks and helper scripts read config at runtime — they are already current.
> - CLAUDE.md is a render-time snapshot — it may now be stale. Run `/update-zskills --rerender` to regenerate the template-managed portion (user-added content below `## Agent Rules` is preserved; conflicts write `CLAUDE.md.new` for manual merge).

**File-path match idiom** (addresses R-C2):
```bash
# Suffix-match: handles absolute, repo-relative, cwd-relative paths.
if [[ "$FILE_PATH" == *".claude/zskills-config.json" ]]; then
  emit_warn
fi
```

**Matcher syntax** (addresses R-C3): current settings.json uses single-string matchers (verified: `"matcher": "Bash"` and `"matcher": "Agent"`). Safer to add two separate entries than to assume compound `"Edit|Write"` is supported (would need a Claude Code docs verification). Exact JSON to add under `"hooks"`:

```json
"PostToolUse": [
  {
    "matcher": "Edit",
    "hooks": [
      {
        "type": "command",
        "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh\"",
        "timeout": 5
      }
    ]
  },
  {
    "matcher": "Write",
    "hooks": [
      {
        "type": "command",
        "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/warn-config-drift.sh\"",
        "timeout": 5
      }
    ]
  }
]
```

(If post-landing we confirm Claude Code supports compound matchers, collapsing to one entry is a trivial follow-up.)

**Settings.json merge**: handled by Phase 2's Step C algorithm (WI 2.5). Phase 3 contributes two new rows to Phase 2's canonical triples table (the Edit + Write matcher rows for warn-config-drift.sh); no separate merge logic lives in Phase 3. The Phase 2 algorithm ensures user-added PreToolUse / PostToolUse entries are preserved across installs, so this plan closes both the original PostToolUse wiring need AND the pre-existing PreToolUse full-overwrite clobber in a single coherent mechanism.

**Non-blocking**: exit 0 always, even on malformed input. A warn hook must never block the user.

**Stderr visibility** (addresses DA-M8): Claude Code PostToolUse hooks emit stderr to the user-visible session output by convention. The acceptance criteria includes a manual smoke test to confirm; if visibility turns out to be buffered/suppressed, Phase 3 lands anyway (warn still fires programmatically) and follow-up adds a user-visible surface via a different channel.

**Install-integrity**: if `warn-config-drift.sh` is missing from source at install time, `/update-zskills` Step C warns the user and skips the PostToolUse wiring rather than writing a settings.json entry that points at a non-existent script. Same pattern as `create-worktree.sh`'s install-integrity check at line 45.

### Acceptance Criteria

- [ ] `hooks/warn-config-drift.sh` exists, is executable, contains the suffix-match idiom and warn text as specified.
- [ ] `.claude/hooks/warn-config-drift.sh` is byte-identical to source.
- [ ] `.claude/settings.json` has two PostToolUse entries (Edit, Write matchers) under `hooks`; PreToolUse array unchanged.
- [ ] All 5 test cases in WI 3.5 pass.
- [ ] Manual smoke test: in a live session, edit `.claude/zskills-config.json` (adding whitespace); observe warn text appears in session output. Documented in phase report. If warn is not visible, document the visibility gap as follow-up without blocking Phase 3 landing.
- [ ] `bash tests/run-all.sh` passes.
- [ ] `skills/update-zskills/SKILL.md` Step C documents the new hook, the install-integrity check, and the conservative settings.json merge behavior.

### Dependencies

Independent of Phase 1 and Phase 2. Any order relative to them.

## Out of Scope

- **E2E_TEST_CMD and BUILD_TEST_CMD fields in config schema**. These remain install-time placeholders because the schema does not carry fields for them. Making them configurable is a separate, smaller plan. If added to config in future, they'd follow this plan's runtime-read pattern (trivially).
- **Changing CLAUDE.md to be runtime-dynamic**. Impossible by nature — markdown isn't executed.
- **Rewriting the config schema**. Only narrow additions at boundary cases (UI_FILE_PATTERNS scoping comment) are in scope.
- **Downstream-consumer re-render broadcasts**. Individual consumers re-run `/update-zskills` (or `--rerender` for CLAUDE.md) once after upgrading to the new zskills version. Commit message notes this.
- **UI object schema nesting**. The scoped regex for `ui.file_patterns` assumes `"ui"` is a flat object of string fields (no nested objects whose values contain `}`). Schema invariant: `ui.*` fields stay flat strings. If future work needs nested `ui` fields, revisit the regex scoping. Phase 1 tests include an assertion over the current schema shape to catch drift.
- **Edit paths outside Claude Code tool invocations**. The PostToolUse drift-warn hook fires only on Claude Code's `Edit` / `Write` tools. Config edits made via `cat >`, `vim`, another editor outside the session, or a direct `gh api` call do not trigger the warn. This is an acknowledged limitation — the warn is a cheap nudge, not a guarantee.
- **Template structural change between releases**. If a future zskills release adds a new heading ABOVE `## Agent Rules` in CLAUDE_TEMPLATE.md, `--rerender` on an old CLAUDE.md will see the structural diff as "user edits" and write `CLAUDE.md.new`. User merges manually. This is the intended behavior — we surface structural changes rather than silently overwriting.

## Disposition Table (Round 1 Review)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R-C1 — --rerender conflict semantics undefined | Reviewer | Verified (plan WI 2.4) | **Fixed** — exit codes (0/1/2), verbatim stderr prompt, boundary algorithm specified in Phase 2 D&C |
| R-C2 — file-path matching ambiguous | Reviewer | Verified (plan WI 3.1) | **Fixed** — suffix match idiom in Phase 3 D&C |
| R-C3 — PostToolUse matcher syntax unverified | Reviewer | Verified — `.claude/settings.json` uses single-string matchers | **Fixed** — two separate entries (Edit, Write); compound syntax is follow-up after verification |
| R-M4 — Drift-regression test incomplete | Reviewer | Verified (WI 1.6 wording) | **Fixed** — WI 1.6 now has both deny-list and allow-list grep loops |
| R-M5 — Insertion point vague | Reviewer | Verified (WI 1.1) | **Fixed** — WI 1.1 specifies "replace lines 225-226 in place" and "delete line 310"; removes placeholder-detection branches at specific line ranges |
| R-m6..9 — Minor test clarity | Reviewer | Verified | **Fixed** — tests now have concrete examples |
| DA-C1 — Empty regex false-positive | DA | Verified by tracing `TEST_PIPE_PATTERN="(|)"` | **Fixed** — explicit empty-pattern guard in Phase 1 D&C |
| DA-C2 — Settings.json PostToolUse merge | DA | Verified — current settings.json nests under `"hooks"`; matcher is single-string | **Fixed** — merge strategy specified (check for existing entry, append only), nested structure corrected |
| DA-C3 — Worktree config path (--show-toplevel vs --git-common-dir) | DA | **Not reproduced** — config is git-tracked; `--show-toplevel` returns branch-current config, matches `is_main_protected()` pattern | **Justified** — document explicitly in D&C; keep `--show-toplevel` for consistency |
| DA-C4 — --rerender boundary detection unspecified | DA | Verified (WI 2.4 vague on algorithm) | **Fixed** — 4-step algorithm in Phase 2 D&C |
| DA-M5 — Dead placeholder-detection code | DA | Verified (lines 229-240, 269-289, 427-445 become dead) | **Fixed** — WI 1.1 explicit cleanup |
| DA-M6 — Test fixture location | DA | Verified | **Fixed** — WI 1.5 specifies `REPO_ROOT=<temp-fixture-dir>` env override |
| DA-M7 — UI_FILE_PATTERNS ambiguity | DA | Verified fragile but current config works | **Fixed** — scoped regex with enclosing `"ui"` prefix; document schema invariant |
| DA-M8 — PostToolUse stderr visibility | DA | Judgment — convention supports stderr visibility | **Justified** — manual smoke test in AC; fallback plan if visibility gap |
| DA-m9 — Fallback docs | DA | Verified | **Fixed** — Phase 1 D&C "Fallback behavior" paragraph |
| DA-m10 — --rerender idempotency | DA | Verified | **Fixed** — idempotency test case added in WI 2.4 |
| DA-m11 — Subdir config resolution | DA | Not reproduced — `--show-toplevel` handles nested cwd | **Fixed** — subdir test case added in WI 1.5 |
| DA-m12 — Downstream transition story | DA | Verified as scope note | **Justified** — Out-of-Scope section added |
| DA-m13 — E2E/BUILD scope | DA | Verified | **Fixed** — Out-of-Scope section added |

All round-1 findings addressed (fixed or justified with evidence-anchored reasoning). No findings ignored or deferred.

## Disposition Table (Round 2 Review)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R2-R-audit — DA-C4 (--rerender "normalize") still hand-wavy | Reviewer | Verified (Phase 2 D&C step 4 used "normalize by substituting prior-known values") | **Fixed** — algorithm simplified: byte-compare with trailing-ws trim; any diff → write `.new`; removed the "normalize" step entirely |
| R2-R — UI regex `[^}]*` fragility | Reviewer | Verified theoretical (current schema safe; fails if future ui field contains nested `{...}`) | **Justified** — documented as schema invariant in Out-of-Scope; WI 1.5 adds assertion over current schema shape |
| R2-R — Headless execution broken by interactive prompt | Reviewer | Verified (Phase 3 D&C said "ask for confirmation") | **Fixed** — prompt removed; merge strategy is deterministic append + stderr NOTICE logging; `/update-zskills` stays headless-safe |
| R2-R — Phase 2 step 4 needs pseudocode | Reviewer | Verified | **Fixed** — concrete 6-step algorithm with exact grep idioms and exit codes |
| R2-R — AC "observe" / "documented in phase report" | Reviewer | Verified (Phase 1 AC line) | **Fixed** — replaced with automated smoke test AC that asserts stderr + rc via a real fixture |
| R2-R — Template-structure drift scenario | Reviewer | Verified | **Justified** — added to Out-of-Scope with explicit intended behavior (conflict → `.new`) |
| R2-R — Minor grep semantics | Reviewer | Minor | **Fixed** — grep idioms now use `-Fq` (fixed-string, quiet) |
| R2-DA — Regex escaping incomplete | DA | Verified (only `.` and space escaped) | **Fixed** — `_zsk_regex_escape` helper covers all bash-regex metacharacters (`\ . ( ) [ ] | * + ? $ ^ { }`) + space-to-`[[:space:]]+` |
| R2-DA — UI `[^}]*` scoping fragile | DA | Same as R2-R UI | **Justified** — schema invariant (see Out-of-Scope) |
| R2-DA — --rerender normalize unspecified | DA | Same as R2-R DA-C4 | **Fixed** — see R2-R DA-C4 disposition |
| R2-DA — Settings.json merge headless | DA | Same as R2-R headless | **Fixed** — see R2-R headless disposition |
| R2-DA — Worktree test gap (DA-C3 follow-up) | DA | Verified — round 1 claimed "justified" but test was missing | **Fixed** — WI 1.5 now includes a worktree-invocation test case |
| R2-DA — Edit outside Claude Code tools | DA | Verified limitation | **Justified** — documented in Out-of-Scope |

All round-2 findings dispositioned. No substantive issues remain; the plan converges.

## Phase 4 — Move zskills-managed content to `.claude/rules/zskills/managed.md`

### Goal

Give zskills its own namespaced, auto-loaded location that it fully owns. Root `./CLAUDE.md` becomes user-exclusive. Supersedes Phase 2's `--rerender` byte-compare design with a simple full-rewrite that can never clobber user content (because no user content lives in `.claude/rules/zskills/`).

### Work Items

- [ ] 4.1 — Edit `skills/update-zskills/SKILL.md` Step B: render template into `.claude/rules/zskills/managed.md` (create the `.claude/rules/zskills/` subdirectory if absent). Stop writing to root `./CLAUDE.md` entirely. Drop the "NEVER overwrite existing CLAUDE.md content" rule; replace with: "zskills owns `.claude/rules/zskills/` in full. User's root `./CLAUDE.md` is theirs exclusively. No cross-writes."

- [ ] 4.2 — Rewrite `### Step D — --rerender` as a simple full-file rewrite of `.claude/rules/zskills/managed.md`. Single success exit code (rc=0); rc=1 only if the template is missing/invalid. No byte-compare, no `.new` file, no boundary algorithm.

- [ ] 4.3 — Mirror SKILL.md changes to `.claude/skills/update-zskills/SKILL.md` (byte-identical).

- [ ] 4.4 — Migration logic in Step B: on every install (first-run and subsequent), detect zskills-rendered content in root `./CLAUDE.md`. For each placeholder in `CLAUDE_TEMPLATE.md`, render its current-config value; grep root `./CLAUDE.md` for lines containing that value within the template's ±2-line context. Lines matching both content AND context are candidates for removal. If any found:
  - Back up root `./CLAUDE.md` to `./CLAUDE.md.pre-zskills-migration` (only if the backup does NOT already exist — never overwrite a prior backup).
  - Remove matched lines from root `./CLAUDE.md`. Everything else untouched.
  - Emit stderr NOTICE: "Migrated zskills content from root ./CLAUDE.md to .claude/rules/zskills/managed.md. Backup: ./CLAUDE.md.pre-zskills-migration."
  - Idempotent: re-running on an already-migrated project is a no-op (nothing to remove, no new backup).

- [ ] 4.5 — Update `hooks/warn-config-drift.sh` + `.claude/hooks/warn-config-drift.sh`: stderr wording references `.claude/rules/zskills/managed.md` specifically (was generic "CLAUDE.md" in Phase 3). Mirror byte-identical.

- [ ] 4.6 — Replace `tests/test-update-zskills-rerender.sh` (459-line byte-compare oracle → ~150 lines). Test cases:
  - Fresh install: `.claude/rules/zskills/managed.md` created, contains current-config values; root `./CLAUDE.md` absent or untouched.
  - `--rerender` after config edit: file reflects new values; no `.new`; rc=0.
  - Migration happy path: fixture with zskills-rendered content in root `./CLAUDE.md` → lines removed, backup at `./CLAUDE.md.pre-zskills-migration`, rules file contains fresh values.
  - Migration no-op: fixture with user-only root `./CLAUDE.md` (no zskills lines) → untouched, no backup.
  - Migration idempotent: run install twice on same fixture; backup still exists only once, root `./CLAUDE.md` unchanged on second run.

- [ ] 4.7 — Update WI 2.7-style structural assertions in `tests/test-skill-conformance.sh`: new Step B wording, new Step D wording, presence of migration block, drift-warn hook references new path. Remove byte-compare and `.new`-file assertions.

### Design & Constraints

**Location choice: `.claude/rules/zskills/managed.md`.** Per Claude Code docs, `.claude/rules/` is auto-loaded recursively at session start, same priority as `.claude/CLAUDE.md`. Files without `paths` frontmatter load unconditionally. Namespaced subdirectory `zskills/` prevents collision with user files or other tools (anyone else uses their own name or the top level of `.claude/rules/`).

**Why NOT `.claude/CLAUDE.md`**: that's a Claude Code documented user-intended project-CLAUDE.md location, co-equal with root `./CLAUDE.md`. Claiming it = squatting on shared address space. Users or other tools could legitimately expect to own it.

**Why NOT `@.claude/…` import from root CLAUDE.md**: requires editing the user's root CLAUDE.md once (to add the `@` line); bootstrap issue if root CLAUDE.md doesn't exist.

**Why a single `managed.md`, not multiple topic files**: Claude Code doesn't document load order for multiple `.md` files in a subdirectory. Single file removes ordering concerns. Can split later.

**Migration detection precision**: content-match alone would false-positive on prose that mentions a value (e.g., "…note we previously used `bash tests/old.sh`…"). Matching content + ±2-line context against the rendered template restricts removal to lines that were genuinely rendered by zskills.

**Backup policy**: `.pre-zskills-migration` created at most once. Prior backups are never overwritten. Users who re-run migration retain their pre-migration state.

**Known caveat**: if a user has `claudeMdExcludes: ["**/.claude/**"]` or similarly broad exclusions in their settings, the rules file will be excluded. Migration NOTICE mentions this for awareness.

### Acceptance Criteria

- [ ] Fresh install on clean project: `.claude/rules/zskills/managed.md` created with rendered content. Root `./CLAUDE.md` untouched.
- [ ] `--rerender` after config edit: `.claude/rules/zskills/managed.md` reflects new values; no `.new` file created; rc=0.
- [ ] Migration happy path: zskills-rendered lines removed from root `./CLAUDE.md`, backup at `./CLAUDE.md.pre-zskills-migration`, rules file contains fresh values, stderr NOTICE emitted.
- [ ] Migration no-op: root `./CLAUDE.md` with no zskills content unchanged; no backup created.
- [ ] Migration idempotent: re-running install does not create a second backup; root `./CLAUDE.md` unchanged.
- [ ] Drift-warn hook: editing `.claude/zskills-config.json` produces stderr containing `.claude/rules/zskills/managed.md` verbatim.
- [ ] `skills/update-zskills/SKILL.md` and `.claude/skills/update-zskills/SKILL.md` byte-identical.
- [ ] All tests pass. 806/806 baseline maintained or improved.

### Dependencies

Phases 1, 2, 3 already landed on `feat/drift-arch-fix`. Phase 4 supersedes Phase 2's Step D (the byte-compare algorithm and its test file are replaced).

## Disposition Table (Round 3 — post-convergence expansion)

| Finding | Source | Evidence | Disposition |
|---|---|---|---|
| R3 — Pre-existing `/update-zskills` Step C full-overwrites `.claude/settings.json`'s `"hooks"` object, clobbering user-added PreToolUse entries on every install | User concern; three adversarial reviews (bail-if-customized, overwrite-if-stock, partition-by-ownership, then research on agent-driven merge) | Verified (`skills/update-zskills/SKILL.md:658-692`: static JSON template shown, no Read+Edit instruction; agents Write whole file) | **Fixed** — Phase 2 scope expanded with WIs 2.5-2.7: Step C rewritten as agent-driven Read+Edit surgical merge, using a canonical zskills-owned triples table, with preview-and-confirm (mirrors Step B's CLAUDE.md pattern) and a Step C.9 rename-migration table for future hook renames |
| R3 — Prior convergence on "defer to followup" was a misapplication of "surface bugs don't patch" | User correction: the CLAUDE.md rule is about agent shortcuts during skill execution, not plan scoping | Updated memory entry `feedback_surface_bugs_scope.md` narrowing the rule's scope | **Fixed** — corrected reasoning; scope expanded to fix PreToolUse clobber within this plan rather than defer |
| R3 — Three prior adversarial reviews rejected bash-splice approaches for this merge | Reviewer consensus: implementation cost and edge cases (orphan entries, nested matcher structure, rename handling) too high in bash | Research agent established precedent: `skills/update-zskills/SKILL.md` already uses agent-driven surgical Read+Edit in 3 other places (lines 608-616, 224-234, 854-858) | **Fixed** — adopted agent-driven Read+Edit to sidestep bash-JSON manipulation entirely |

## Plan Quality

- **Drafting process**: `/draft-plan` with 2 formal rounds of adversarial review + 1 post-convergence scope expansion prompted by user review and two targeted adversarial agent dispatches (partition-by-ownership rejection, then agent-driven merge research + precedent-finding).
- **Convergence**: converged at round 2 with narrow scope; the round-3 expansion surfaced a pre-existing bug (settings.json full-overwrite) that belonged in this plan's charter but was initially out-of-scope due to a misapplied "surface don't patch" framing. Once reframed as agent-driven Read+Edit (rather than bash-JSON-splice), the fix collapsed to a small set of additions.
- **Verify-before-fix discipline**: every finding across all three rounds dispositioned with evidence anchor — 29 fixed, 4 justified. Zero deferred or ignored within scope.
- **Remaining concerns**: none blocking; two acknowledged limitations in Out-of-Scope (edits outside Claude Code tools don't fire the drift-warn hook; template structural changes between releases trigger `.new` conflict by design).

### Round History

| Round | Reviewer Findings | DA / Research Findings | Resolved |
|-------|-------------------|------------------------|----------|
| 1     | 5 (3 critical, 2 major, 4 minor)  | 13 (4 critical, 4 major, 5 minor)  | 17/17 (15 fixed, 2 justified) |
| 2     | 6 (1 audit, 2 critical, 3 minor)  | 6 (4 critical, 2 minor)            | 13/13 (11 fixed, 2 justified; critical claims verified as real) |
| 3     | User concern + 3 targeted agent reviews (bail-if-customized, partition-by-ownership, agent-driven-merge precedent) | Agent-driven Read+Edit precedent established in same skill (608-616, 224-234, 854-858) | 3/3 fixed — scope expanded to include settings.json clobber fix via agent-driven merge |

