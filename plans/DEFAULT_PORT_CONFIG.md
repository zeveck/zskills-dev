---
title: Default Port Config — Schema-Driven, Runtime-Read
created: 2026-04-25
status: draft
---

# Plan: Default Port Config — Schema-Driven, Runtime-Read

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

zskills hardcodes port `8080` in seven places (port.sh, test-all.sh, briefing.py, briefing.cjs, the rendered template prose, plus minor docs). Consumers running Django (8000), Rails (3000), Vite (5173), Next.js (3000), etc. get the wrong port reported and written into their `managed.md`. The only override today is the per-invocation `DEV_PORT` env var.

This plan eliminates the hardcoded value by making port a configurable schema field — `dev_server.default_port`, integer, schema default `8080`. `/update-zskills` writes the field on greenfield install and backfills it into existing configs (mirroring the established `commit.co_author` backfill pattern). The runtime consumers (`port.sh`, `test-all.sh`) read the field via the canonical bash-regex pattern landed in DRIFT_ARCH_FIX Phase 1, with the scope-bound tightened to `[^{}]*` to be safe under future nested-object additions; no code-level fallback. `briefing.py` and `briefing.cjs` drop their literal `'8080'` and gracefully omit URLs when port determination fails.

The plan is split into 5 phases. Phase 1 lands the field (schema + this-repo config + /update-zskills writes/backfills) so that consumers running `/update-zskills` after pulling will have the field present before any later phase needs it. Phase 2 then migrates `port.sh` and `test-all.sh` to read the field and adds a `PROJECT_ROOT` env override so that test fixtures can isolate the script from this repo's own config. The renderer, drift-warn hook, and pattern are all already landed from DRIFT_ARCH_FIX.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Schema field + /update-zskills greenfield write & backfill | ⬚ | | |
| 2 — port.sh + test-all.sh runtime-read + PROJECT_ROOT env override | ⬚ | | |
| 3 — Template `{{DEFAULT_PORT}}` placeholder + Step B mapping | ⬚ | | |
| 4 — briefing.py / briefing.cjs sync | ⬚ | | |
| 5 — Documentation surfaces | ⬚ | | |

## Phase 1 — Schema field + /update-zskills greenfield write & backfill

### Goal

Add `dev_server.default_port` (integer, default 8080) to the schema; ensure every consumer's `.claude/zskills-config.json` will contain the field after running `/update-zskills` (greenfield write on fresh install, backfill on existing configs); add the field to this repo's own config so subsequent phases can rely on it. No script behavior changes yet.

### Work Items

> **Overlap warning.** `plans/SCRIPTS_INTO_SKILLS_PLAN.md` Phase 3a WI 3a.4c makes the same `dev_server.default_port` schema-field addition (its sub-WIs 3a.4c.i and 3a.4c.iii) plus the same edits to this repo's config, the `update-zskills` greenfield template, and the schema. Whichever plan lands first, the WIs in this Phase 1 (specifically 1.1, 1.2, 1.3) become no-ops or duplicate edits. **Run `/refine-plan plans/DEFAULT_PORT_CONFIG.md` before `/run-plan` if SCRIPTS_INTO_SKILLS_PLAN landed first** to drop the redundant WIs and re-validate the backfill (1.4) — backfill is the surviving novel work since SCRIPTS_INTO_SKILLS does not implement backfill for existing configs. Phases 2-5 (port.sh + test-all.sh runtime read, briefing scripts, template placeholder, docs) remain in scope regardless of order.

- [ ] 1.1 — Edit `config/zskills-config.schema.json`. Add a `default_port` property under `dev_server.properties` (after `main_repo_path`):
  - Type: `integer`
  - Default: `8080`
  - Description: `"Default port the main repo's dev server uses. Worktrees get a deterministic hash-derived port. Override per-invocation with the DEV_PORT env var."`

- [ ] 1.2 — Edit this repo's `.claude/zskills-config.json` to add `"default_port": 8080` inside the existing `dev_server` block (after `main_repo_path`). This is required for Phase 2's `port.sh` change to function in this repo without breaking the test suite.

- [ ] 1.3 — Edit `skills/update-zskills/SKILL.md` Step 0.5 (the greenfield install JSON template, around lines 262-296). Add `"default_port": 8080` inside the `dev_server` block of the template that gets written via the `Write` tool on first install.

- [ ] 1.4 — Edit `skills/update-zskills/SKILL.md` Step 0.5 step 3.5 (the existing `commit.co_author` backfill block). Add `dev_server.default_port` to the list of backfilled fields. The implementation pattern:
  - Detect whether the existing `dev_server` block contains a `"default_port"` field.
  - If absent: insert `"default_port": 8080` immediately before the `}` closing the `dev_server` block (append-before-closing-brace is order-independent; works regardless of the current last field). The previous last field gets a trailing comma added in the same operation.
  - If the entire `dev_server` block is absent (very old config): write the whole block with `"cmd": ""`, `"port_script": ""`, `"main_repo_path": ""`, `"default_port": 8080`.
  - Idempotent: re-running on a config that already has the field is a no-op.

- [ ] 1.5 — Mirror the source-skill edit to `.claude/skills/update-zskills/SKILL.md` via batched cp from the worktree root:
  ```bash
  rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/
  ```
  Both `skills/` and `.claude/skills/` changes commit together inside the worktree.

- [ ] 1.6 — Update `tests/test-update-zskills-rerender.sh` (or add a new test if cleaner) to cover three cases:
  - **Greenfield**: a fresh install writes `"default_port": 8080` inside the `dev_server` block of the new config.
  - **Backfill**: an existing config without the field gets `"default_port": 8080` appended after the backfill code path runs; every other field preserved byte-for-byte.
  - **Idempotency**: running the backfill twice produces the same output.

### Design & Constraints

**Why integer, not string?** The schema already mixes types (`max_fix_attempts: integer`, `main_protected: boolean`, others string). A port is semantically an integer; using `integer` lets a future schema validator catch typos like `"8080"` as a string. Bash regex reads integers cleanly via `([0-9]+)`. (Verified in round 2: a string-typed `"default_port": "8080"` value FAILS to match the integer regex, which surfaces the typo as a fail-loud error rather than capturing a wrong value silently.)

**Schema `"default"` is informational only.** zskills does not currently run a schema validator at install. `/update-zskills` Step 0.5 writes the install JSON via the `Write` tool from a literal template; it does not derive the value from the schema. So `8080` lives in three places after this phase: (a) the schema's `"default": 8080`, (b) the install template's literal `"default_port": 8080` (WI 1.3), and (c) the backfill default `8080` (WI 1.4). Acceptance criteria below verify all three say the same thing. Single-sourcing them is future work — see Out of Scope.

**Backfill placement: insert before closing brace.** The append-before-`}` operation is order-independent — it works whether the current last field is `main_repo_path` (today's shape) or anything else. The previous last field gets a trailing comma added in the same operation. The existing `commit.co_author` backfill at `skills/update-zskills/SKILL.md` Step 0.5 step 3.5 is the pattern; this WI follows the same shape.

**Nested-object ordering constraint (forward-compat).** The Phase 2 regex (`[^{}]*` scoped to the enclosing `dev_server` object) does NOT traverse nested objects. If `dev_server` ever gains a nested object property in the future, `default_port` MUST appear in the JSON serialization BEFORE the nested object, or it won't be matched. This is a theoretical concern today (no nested-object precedent) but worth documenting because IDE JSON formatters can re-sort keys; a future "add a nested object to dev_server" change must keep this invariant. If JSON-key sorting becomes routine, the regex-based reader needs replacement (out of scope here).

**No script behavior changes in Phase 1.** `port.sh` and `test-all.sh` continue to use their hardcoded `8080`; nothing is broken by Phase 1 alone. **Inter-phase window:** between this phase landing and Phase 2 landing, `port.sh` ignores the new `default_port` field. The schema documents the field with type `integer` and default `8080`, which may invite consumers to edit it; until Phase 2 lands, those edits will not affect `port.sh`'s output. Release notes / CHANGELOG should mention this (one-paragraph "field added in Phase 1; consumers honored in Phase 2").

### Acceptance Criteria

- [ ] `config/zskills-config.schema.json` contains `default_port` under `dev_server.properties` with `"type": "integer"` and `"default": 8080`. Verify: `grep -A2 '"default_port"' config/zskills-config.schema.json` shows the field with type and default.
- [ ] This repo's `.claude/zskills-config.json` contains `"default_port": 8080` inside `dev_server`. Verify: `grep '"default_port"' .claude/zskills-config.json` matches.
- [ ] `skills/update-zskills/SKILL.md` greenfield JSON template (Step 0.5) contains `"default_port": 8080` inside the `dev_server` block. Verify: `grep -A1 '"default_port"' skills/update-zskills/SKILL.md` matches the install template.
- [ ] `skills/update-zskills/SKILL.md` backfill block (Step 0.5 step 3.5) names `dev_server.default_port` as a backfilled field. Verify: `grep -B1 -A3 'default_port' skills/update-zskills/SKILL.md` shows the backfill instruction.
- [ ] `skills/update-zskills` and `.claude/skills/update-zskills` are byte-identical: `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] `tests/test-update-zskills-rerender.sh` includes greenfield, backfill, and idempotency cases for `dev_server.default_port`, all passing.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

None. First phase.

## Phase 2 — `port.sh` + `test-all.sh` runtime-read + `PROJECT_ROOT` env override

### Goal

Migrate `scripts/port.sh` and `scripts/test-all.sh` to read `dev_server.default_port` from the config at runtime via the canonical bash-regex pattern. Add a `PROJECT_ROOT` env override (mirroring the existing `REPO_ROOT` override) so that test fixtures can isolate the scripts from this repo's own config. Remove the hardcoded `DEFAULT_PORT=8080` literal and the `echo 8080` fallback. When the field is absent (pathological — Phase 1 ensured it's present in every `/update-zskills`-installed config), fail loud with a clear actionable message — no code-level fallback. Update `tests/test-port.sh` to assert the new behavior using a temp-directory fixture under `/tmp/`.

### Work Items

- [ ] 2.1 — Refactor `scripts/port.sh`:
  - Add a `PROJECT_ROOT` env override at line 11-12. Replace the unconditional `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"` with `PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`. This mirrors the existing `REPO_ROOT` override at line 16 and is required for fixture-based testing in WI 2.3.
  - Read both `dev_server.main_repo_path` and `dev_server.default_port` from a single `_ZSK_CFG_BODY` read. Concretely: move the `unset _ZSK_CFG_BODY` to AFTER the new `default_port` regex (so a single read serves both extracts).
  - Read `default_port` via the integer regex with the tightened scope-bound:
    ```bash
    if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^{}]*\"default_port\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
      DEFAULT_PORT="${BASH_REMATCH[1]}"
    fi
    ```
    Note `[^{}]*`, NOT `[^}]*`. The tighter pattern refuses to traverse a nested object (verified in round 1: with `[^}]*`, a fixture `{"dev_server": {"limits": {"default_port": 9999}, "default_port": 3000}}` falsely captures `9999`; with `[^{}]*`, no match, which is correct).
  - Remove the literal `DEFAULT_PORT=8080` at line 29-30.
  - Rewrite the header comment at port.sh:4-5 to describe the new model: "Main repo (dev_server.main_repo_path, read at runtime) -> dev_server.default_port (read at runtime). Worktrees -> stable port in 9000-60000 derived from the project root path."
  - When `DEFAULT_PORT` is empty after the runtime read AND the project root matches `MAIN_REPO`, print this message to stderr and exit non-zero:
    ```
    port.sh: dev_server.default_port not set in $_ZSK_CFG. Open this repo in Claude Code and run /update-zskills to backfill the field, or set DEV_PORT=NNNN env var to override per-invocation.
    ```
    The message MUST include the resolved absolute path (`$_ZSK_CFG`) so the user knows exactly which file is missing the field. The message MUST clarify that `/update-zskills` is a Claude Code slash command (not a shell command).
  - DEV_PORT env var override unchanged (still wins; checked first).
  - Worktree-hash logic unchanged.

- [ ] 2.2 — Apply the equivalent refactor to `scripts/test-all.sh`'s `get_port()` function (around lines 56-78):
  - Add a `PROJECT_ROOT` env override. Replace line 63's `project_root="$(cd "$SCRIPT_DIR/.." && pwd)"` with `project_root="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`. The `local project_root` declaration on line 62 is unchanged. Order matters: this assignment must precede the `_cfg_root` line at 65 (which reads `$project_root` via `git -C "$project_root"`); the existing line ordering is already correct.
  - Add the `default_port` regex match against the existing local `_body` config-body variable (already function-scoped, so just add the second match using the integer regex with `[^{}]*` scope-bound — same pattern as WI 2.1).
  - Remove `echo 8080` at line 76. On absent field with project root matching main repo, print to stderr and `return` non-zero (same actionable message as port.sh, with absolute config path).

- [ ] 2.3 — Update `tests/test-port.sh`:
  - Existing tests for determinism, DEV_PORT override, range, and numeric output: unchanged.
  - Replace any test that asserts `port == 8080` for the main-repo case with a fixture-based assertion using both `REPO_ROOT` AND `PROJECT_ROOT` env overrides (added in WI 2.1):
    ```bash
    FIXTURE=/tmp/zskills-port-fixture
    rm -rf "$FIXTURE" && mkdir -p "$FIXTURE/.claude"
    cat > "$FIXTURE/.claude/zskills-config.json" <<JSON
    {"dev_server": {"main_repo_path": "$FIXTURE", "default_port": 7777}}
    JSON
    out=$(REPO_ROOT="$FIXTURE" PROJECT_ROOT="$FIXTURE" bash "$PORT_SCRIPT")
    [[ "$out" == "7777" ]] || fail "fixture default_port — expected 7777, got $out"
    rm -rf "$FIXTURE"
    ```
    (Round 2 verified that without the WI 2.1 `PROJECT_ROOT` override, `port.sh` recomputes `PROJECT_ROOT` from `SCRIPT_DIR/..` and the env var is silently ignored. WI 2.1 makes this fixture mechanism work.)
  - Add a new test case: when `default_port` is removed from the fixture config (different fixture path: `/tmp/zskills-port-fixture-absent`), `bash "$PORT_SCRIPT"` exits non-zero AND stderr contains `default_port`.
  - Add a fixture test confirming `PROJECT_ROOT` env override works: set `PROJECT_ROOT` to a fixture, expect that fixture's `default_port` value (different from this repo's).

### Design & Constraints

**Why add `PROJECT_ROOT` env override.** Without it, `port.sh` recomputes `PROJECT_ROOT` from its own `SCRIPT_DIR/..`, which always points at this repo. Any fixture-based test that needs to make `port.sh` see a different "main repo" is impossible. Adding the env override is a small interface improvement that costs one line and makes the entire fixture strategy in WI 2.3 work. The existing `REPO_ROOT` override (line 16) already establishes the pattern.

**Tighter regex scope-bound.** Use `[^{}]*` instead of `[^}]*` to refuse traversal into nested objects under `dev_server`. The existing `main_repo_path` block uses `[^}]*`, which is theoretically vulnerable to the same issue but lower-risk in practice (string field, less likely to be duplicated under a nested object). This phase introduces the safer pattern for the new field; tightening the existing block is a sweep candidate but not required (out of scope).

**Single-read refactor: shared cfg-body.** `port.sh` currently does `unset _ZSK_CFG_BODY` inside the existing `if [ -f "$_ZSK_CFG" ]` block. Move that `unset` AFTER both regex matches run. `test-all.sh` already keeps `_body` function-scoped, so just add the second regex match against `_body`.

**No code-level fallback.** Per CLAUDE.md "no premature back-compat" and the user's explicit guidance: when the field is absent, fail loud (exit non-zero, stderr message). Do not add a "default to 8080 if absent" branch in the script — the schema default + Phase 1 backfill is the single mechanism that ensures presence.

**Loud-fail message specificity.** The message includes the resolved absolute config path AND clarifies that `/update-zskills` is a Claude Code slash command. A user running `bash scripts/port.sh` from a terminal needs to know (a) which config file is missing the field, and (b) that `/update-zskills` is invoked inside Claude Code, not at the shell. This avoids the under-specification flagged in round 2.

**Inter-phase transition (Phase 1 → Phase 2 window).** Between Phase 1's land and Phase 2's land, `port.sh` and `test-all.sh` still hardcode `8080` and ignore `default_port`. A consumer who edits `default_port` between phases will not see the script honor it until Phase 2 lands. Document in CHANGELOG / release notes when both phases ship.

**Test-fixture isolation under `/tmp/zskills-port-fixture` literal paths.** This is per the project's safety-hook policy that permits literal `/tmp/<name>` paths but blocks variable expansion. The `rm -rf` cleanup must use the literal path, not a variable.

### Acceptance Criteria

- [ ] `grep -nE '^[^#]*\b8080\b' scripts/port.sh` returns no matches (no literal 8080 outside header doc-comment, which is rewritten in WI 2.1).
- [ ] `grep -nE '^[^#]*\b8080\b' scripts/test-all.sh` returns no matches.
- [ ] `scripts/port.sh` honors a `PROJECT_ROOT` env override. Verify: `PROJECT_ROOT=/tmp/somepath bash scripts/port.sh` (with appropriate fixture) uses that path as the project root.
- [ ] `bash scripts/port.sh` from this repo's root prints `8080` (the configured default in this repo's `.claude/zskills-config.json`).
- [ ] In a fixture config with `"default_port": 7777`, `REPO_ROOT=<fixture> PROJECT_ROOT=<fixture> bash scripts/port.sh` prints `7777`.
- [ ] In a fixture config without `default_port`, `REPO_ROOT=<fixture> PROJECT_ROOT=<fixture> bash scripts/port.sh` exits non-zero AND stderr contains `default_port` AND stderr contains the absolute config path.
- [ ] `bash scripts/test-all.sh` works as before in this repo (no broken test fixtures).
- [ ] `tests/test-port.sh` includes the new fixture-based cases (PROJECT_ROOT override, configured default, absent-field fail-loud), all passing.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (the schema field and this-repo config update must be present before this phase's runtime-read can find anything in the repo's own config).

## Phase 3 — Template `{{DEFAULT_PORT}}` placeholder + Step B mapping (incl. `{{MAIN_REPO_PATH}}` fix)

### Goal

Eliminate the hardcoded `**8080**` prose in `CLAUDE_TEMPLATE.md:13` so consumers' rendered `managed.md` shows their actual configured port. **Decision: Option A** (introduce a `{{DEFAULT_PORT}}` placeholder substituted from `dev_server.default_port` at install/--rerender). Rationale below. Also fix the missing `{{MAIN_REPO_PATH}}` placeholder mapping that currently leaks unsubstituted into rendered files (round 2 finding).

### Work Items

- [ ] 3.1 — Edit `CLAUDE_TEMPLATE.md:13`. Replace the literal `**8080**` with `**{{DEFAULT_PORT}}**`. The full line becomes:
  > The port is determined automatically by `{{PORT_SCRIPT}}`: **{{DEFAULT_PORT}}** for the main repo (`{{MAIN_REPO_PATH}}`), a **deterministic unique port** for each worktree (derived from the project root path). Run `bash {{PORT_SCRIPT}}` to see your port. Override with `DEV_PORT=NNNN` env var if needed.

- [ ] 3.2 — Edit `skills/update-zskills/SKILL.md` placeholder mapping table (around lines 321-329). Add TWO rows:
  ```
  | `{{DEFAULT_PORT}}` | `dev_server.default_port` | `8080` |
  | `{{MAIN_REPO_PATH}}` | `dev_server.main_repo_path` | `/path/to/repo` |
  ```
  The `{{MAIN_REPO_PATH}}` row is a **bug fix** unrelated to `default_port`: that placeholder is already used in `CLAUDE_TEMPLATE.md:13` but is not in the substitution mapping today, so consumer renders contain a literal `{{MAIN_REPO_PATH}}` substring. While the plan touches the same prose line, fixing this missing mapping is "while you're there" hygiene; deferring leaves an obvious-on-inspection unsubstituted placeholder.

- [ ] 3.3 — Edit `skills/update-zskills/SKILL.md` Step B's substitution logic (around lines 596-693) to handle BOTH new placeholders. Integer-vs-string distinction: `{{DEFAULT_PORT}}` substitutes the digits without surrounding quotes (the placeholder is in markdown prose, not JSON). `{{MAIN_REPO_PATH}}` substitutes the path string. Both are read from `.claude/zskills-config.json` the same way other fields are read.

- [ ] 3.4 — Reconcile `skills/update-zskills/SKILL.md:329`. That line currently reads: "Runtime-read fields (not install-filled): `testing.unit_cmd`, `testing.full_cmd`, `ui.file_patterns`, `dev_server.main_repo_path`." This conflicts with WI 3.2 adding `{{MAIN_REPO_PATH}}` to the install-substitution mapping. The reconciliation: `dev_server.main_repo_path` is BOTH runtime-read (by `port.sh`/`test-all.sh` scripts at every invocation, so they stay current with config edits) AND install-substituted (into the managed.md template prose, so consumers see the path on the page; drift mitigated by warn-config-drift on Edit/Write paths). Update line 329 to either (a) remove `dev_server.main_repo_path` from the runtime-read-only list and add a note that it's runtime-read by scripts AND install-substituted in prose, or (b) restructure the prose to make the dual-role explicit.

- [ ] 3.5 — Mirror the source-skill edit to `.claude/skills/update-zskills/SKILL.md` via batched cp from the worktree root:
  ```bash
  rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/
  ```

- [ ] 3.6 — Update `tests/test-update-zskills-rerender.sh` to assert:
  - A fresh install with `default_port: 8080` produces `managed.md` whose corresponding line contains the literal `**8080** for the main repo`.
  - Editing the config to `default_port: 3000` and running `/update-zskills --rerender` produces `managed.md` containing `**3000** for the main repo`.
  - `{{MAIN_REPO_PATH}}` is also substituted (no leftover placeholder).
  - The rendered `managed.md` contains no leftover `{{DEFAULT_PORT}}` or `{{MAIN_REPO_PATH}}` placeholder.

### Design & Constraints

**Decision rationale (Option A vs Option B):**

The placeholder approach (A) wins on two grounds:

1. **User-visible UX.** A consumer reading their `managed.md` sees "**3000** for the main repo" — concrete, no extra step. Option B forces them to run `bash {{PORT_SCRIPT}}` to find out. The agent reading the file gets the same benefit.

2. **Consistency with existing placeholders.** `{{DEV_SERVER_CMD}}`, `{{PORT_SCRIPT}}`, `{{MAIN_REPO_PATH}}` are already substituted into the same prose. A new placeholder fits the established pattern; generic prose breaks the convention for one field only.

**Drift risk and its mitigation — honest scope.** `hooks/warn-config-drift.sh` fires a generic NOTICE when `.claude/zskills-config.json` is edited via Claude Code's `Edit` or `Write` tool calls (`.claude/settings.json:30-51` wires only those two PostToolUse matchers). This means the hook DOES NOT fire for:
- Edits made in an external editor / IDE
- `git pull` updating the config (teammate landed a config change)
- `sed`-style command-line edits (Bash tool, not Edit tool)
- CI workflow modifications
- `gh secret set` or similar external tooling

So Option A's drift mitigation covers a minority of plausible edit paths — only those that flow through Claude Code's `Edit` or `Write` tool. It IS a real backstop for "user changed config in Claude Code session," not a comprehensive guarantee of `managed.md` freshness. Habituation to the generic notice is also a real risk.

We accept Option A despite this, because: (a) the UX win is real (concrete number on the page), (b) Option B's "run port.sh to see your port" is itself drift-immune but creates per-read friction, and (c) field-aware drift detection (e.g., a SessionStart hook hashing the config) is a separate enhancement we can add later (see Out of Scope).

### Acceptance Criteria

- [ ] `grep -c '8080' CLAUDE_TEMPLATE.md` returns 0.
- [ ] `grep -c '{{DEFAULT_PORT}}' CLAUDE_TEMPLATE.md` returns 1 (the new placeholder).
- [ ] `skills/update-zskills/SKILL.md` placeholder mapping table includes `{{DEFAULT_PORT}}` AND `{{MAIN_REPO_PATH}}` rows. Verify: `grep -E '\{\{(DEFAULT_PORT|MAIN_REPO_PATH)\}\}' skills/update-zskills/SKILL.md` matches both.
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] In a sandbox fixture install at `/tmp/zskills-render-fixture` with `default_port: 3000`, the rendered `managed.md` contains the literal `**3000** for the main repo` and no `{{DEFAULT_PORT}}` substring.
- [ ] After editing the fixture config to `default_port: 5173` and re-rendering, `managed.md` contains `**5173** for the main repo`.
- [ ] In the same fixture, `{{MAIN_REPO_PATH}}` is also fully substituted (no `{{MAIN_REPO_PATH}}` substring in the rendered file).
- [ ] `skills/update-zskills/SKILL.md:329` no longer classifies `dev_server.main_repo_path` as runtime-read-only (per WI 3.4). The line either lists it under both runtime-read and install-substituted, or restructures the prose to make the dual role explicit.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (the schema field and consumer-config presence is what the placeholder substitutes from).

## Phase 4 — `briefing.py` / `briefing.cjs` sync, drop literal, omit-URL on failure

### Goal

Drop the `'8080'` literal fallback from both `briefing.py` and `briefing.cjs`. When `port.sh` returns empty or fails, briefing gracefully degrades (omits the localhost URL) instead of fabricating one with the wrong port. Maintain byte-equivalent port-handling logic between the two implementations as a checkable invariant.

### Work Items

- [ ] 4.1 — Edit `scripts/briefing.py` at the four enumerated `viewer_url` / port-fallback sites. (Verified in round 2 by `grep -n viewer_url`: exactly two URL emission sites in briefing.py.)
  - **Inline-URL site, `briefing.py:859-860`** (pattern `lines.append(f' {topic} ({len(items)}) — {viewer_url}')`): when `port` is `None`, emit the line WITHOUT the `— {viewer_url}` suffix (i.e., `lines.append(f' {topic} ({len(items)})')`).
  - **Separate-line URL site, `briefing.py:1133-1135`** (pattern `lines.append(f' {viewer_url}')` as its own line): when `port` is `None`, skip this `lines.append` call entirely.
  - **Port-fallback sites, `briefing.py:798-805` and `briefing.py:1109-1116`**: remove the `port = '8080'` initializer; remove the `or '8080'` fallback after the `run(f'bash {port_sh}', ...)` call. When port.sh is missing OR returns empty OR raises, set `port = None`.
  - Rewrite the surrounding comments (e.g., `# Get port for localhost URLs via port.sh; default 8080.`) to reflect the new behavior, e.g., `# Get port via port.sh; omit URL section on failure.`

- [ ] 4.2 — Apply the equivalent edits to `scripts/briefing.cjs`. The two URL emission sites (verified by round-2 grep `viewer_url`) are at briefing.cjs:780 (inline) and briefing.cjs:1101 (separate-line). The four port-fallback sites Agent 1 identified are at briefing.cjs:703-704, 708, 710, 1077-1078, 1082, 1084 — verify exact lines by grep before editing; the structure mirrors briefing.py's two `port = ...` blocks.

- [ ] 4.3 — Add a one-paragraph py/cjs invariant note at the top of both `scripts/briefing.py` and `scripts/briefing.cjs`:
  ```
  # ZSKILLS INVARIANT: briefing.py and briefing.cjs are intentional Python/Node mirrors.
  # Their port-handling behavior, output structure, and degradation semantics MUST stay byte-equivalent
  # except for language idioms (`'` vs `"`, `None` vs `null`, comment syntax). Edits to one require
  # a parity edit to the other.
  ```
  Use comment syntax appropriate to each language (`#` for Python, `//` for JS).

- [ ] 4.4 — Add a behavioral test at `tests/test-briefing-port-failure.sh` (or extend an existing briefing test):
  - Set up a fixture where port.sh exits non-zero. Use `/tmp/zskills-briefing-fixture` (literal path).
  - Run briefing.py and briefing.cjs against the fixture.
  - Assert: neither emits a localhost URL (search the output for `localhost:` and expect zero matches).
  - Assert: both run to completion (no exception/crash; exit 0).
  - Assert: their output structures are byte-equivalent. Implementation: first run `grep -nE '(None|null|True|False|true|false)\b' scripts/briefing.{py,cjs}` to enumerate any language-specific literals that leak into stdout. If the grep finds any, EITHER (a) refactor the source to ensure no language-specific literals reach stdout (preferred — both implementations should emit equivalent text), OR (b) document the specific list of normalizations needed (e.g., "regex `s/None/null/g`") and apply it before the diff. Do NOT use vague "normalize for language differences" as the test spec; commit to either byte-equivalent output or an enumerated rule list.

### Design & Constraints

**Why drop the fallback entirely?** With Phase 1's `default_port` field schema-defaulted to 8080 and backfilled into every consumer's config, port.sh failure is the pathological case (only happens if the user removes the field by hand or `port.sh` itself errors). Briefing's `'8080'` literal therefore covers a path that should never be taken in practice; keeping it would mask the underlying issue.

**Why omit the URL rather than substitute a placeholder?** A URL with a wrong port is worse than no URL — users will click and get a connection-refused. Better to indicate "port unavailable" by silence than to fabricate.

**py/cjs sync.** These files are a Python/Node mirror for compat (one runs on Python, the other on Node). Their port-handling logic should always be identical. WI 4.3 (the invariant comment) and WI 4.4 (the parity test) make this an explicit, checkable invariant.

### Acceptance Criteria

- [ ] `grep -c '8080' scripts/briefing.py` returns 0.
- [ ] `grep -c '8080' scripts/briefing.cjs` returns 0.
- [ ] Both files have the invariant comment at the top (see WI 4.3 wording).
- [ ] In the `/tmp/zskills-briefing-fixture` test, both briefing.py and briefing.cjs run to completion (exit 0) and emit no `localhost:` URL.
- [ ] Their output structures are equivalent on the fixture (parity test passes).
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 2 (port.sh's new fail-loud-on-absent-field behavior is what this phase relies on; without it, the briefing fallback path can't be tested).

## Phase 5 — Documentation surfaces

### Goal

Bring the remaining hardcoded `8080` references in active documentation in line with the new model. Keep skills' source and `.claude/skills/` mirrors in sync.

### Work Items

- [ ] 5.1 — Edit `skills/briefing/SKILL.md` lines 141, 151, 158. Replace each instance of `localhost:8080/...` with `localhost:<your-port>/...`. Use the canonical replacement consistently across all three sites; do not vary the wording.

- [ ] 5.2 — Edit `skills/manual-testing/SKILL.md` line 18. Update the comment "(8080 for main, unique per worktree)" to "(configured via dev_server.default_port for main, unique per worktree)".

- [ ] 5.3 — Mirror both skill source edits to their `.claude/skills/` counterparts via batched cp from the worktree root:
  ```bash
  rm -rf .claude/skills/briefing && cp -r skills/briefing .claude/skills/
  rm -rf .claude/skills/manual-testing && cp -r skills/manual-testing .claude/skills/
  ```

### Design & Constraints

**What's out:**
- `plans/ZSKILLS_MONITOR_PLAN.md:80` — historical plan artifact. Leave alone (per the same hygiene rule used for PR #62: don't edit `plans/` or `reports/`).
- `tests/test-hooks.sh` `:8080` substrings — out of scope from the plan's Overview (deny-pattern test strings).
- `CLAUDE.md:18` (the `<!-- Serve locally with: npx http-server -p 8080 -->` HTML-commented-out aside in this repo's own CLAUDE.md, not consumer-facing). Round 2 verified this isn't read by any tool, isn't rendered into any consumer artifact, and is purely an HTML-author convenience aside. **Leave alone.**

### Acceptance Criteria

- [ ] `grep -c '8080' skills/briefing/SKILL.md` returns 0.
- [ ] `grep -c '8080' skills/manual-testing/SKILL.md` returns 0 (the in-scope comment is rewritten).
- [ ] `diff -rq skills/briefing .claude/skills/briefing` empty.
- [ ] `diff -rq skills/manual-testing .claude/skills/manual-testing` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1-4. (Conceptually independent of Phases 2-4, but landing last avoids merge thrash with the substantive changes.)

## Out of Scope

- **Auto-detection from framework conventions** (Vite, Django, Rails, etc.). User decision: deferred. Each consumer sets `dev_server.default_port` manually in their config; the schema default of `8080` is the universal starting point. A future plan can revisit if user demand emerges.
- **Single-sourcing the `8080` default across schema, install template, and backfill.** Today the default lives in three places (`config/zskills-config.schema.json` schema default, `skills/update-zskills/SKILL.md` install template literal, `skills/update-zskills/SKILL.md` backfill default value). This plan keeps them in sync via acceptance criteria but does not eliminate the duplication. A future refactor could derive install-template values from the schema; that's a `/update-zskills`-shape change, not a port-config change.
- **Broadening `warn-config-drift` coverage to non-Edit/non-Write paths.** Today the hook fires only on Claude Code `Edit` and `Write` PostToolUse matchers. External edits (IDE, `git pull`, `sed`, `gh secret set`, Bash tool, CI workflows) bypass it entirely. A SessionStart-hook approach that hashes the config and compares against last-render snapshot would close most of the gap; that's a separate `warn-config-drift.sh` enhancement, not a port-config change.
- **`tests/test-hooks.sh` `:8080` deny-pattern substrings.** These test that the safety hook blocks `fuser -k <port>` regardless of port number; leaving them alone preserves the test's invariant.
- **`plans/ZSKILLS_MONITOR_PLAN.md` historical reference.** Plan-archive hygiene: don't edit `plans/` or `reports/`.
- **Tightening the existing `main_repo_path` regex from `[^}]*` to `[^{}]*`.** Theoretically vulnerable to the same nested-object issue this plan tightens for `default_port`, but lower-risk in practice (string field, no nested-object precedent in `dev_server`). Out of scope; can be done as a sweep in a follow-up.
- **SCRIPTS_INTO_SKILLS coupling.** If `SCRIPTS_INTO_SKILLS_PLAN` lands at any point during this plan's execution — before OR between phases — pause and run `/refine-plan plans/DEFAULT_PORT_CONFIG.md` to update file paths to the new layout. Specifically, do not start a new phase without verifying the file paths in remaining phases are current; `/run-plan` in PR mode runs phases asynchronously, so mid-execution drift is a real risk.

## Drift Log

(Empty — populated during execution by `/run-plan` if Phases get refined.)

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review.
**Convergence:** Round 3 surfaced 2 medium issues (line-329 reconciliation conflicting with WI 3.2's mapping addition; WI 2.2 PROJECT_ROOT override under-specified vs WI 2.1's literal patch) plus one medium quality concern (WI 4.4 normalization "etc." vague). All three were fixed during round-3 refinement; remaining round-3 findings were either confirming (round-2 fix verified) or self-rejected on empirical check by the DA. Default rounds=3 reached; not running round 4. The plan is ready to execute.
**Remaining concerns:** None blocking. Inter-phase transition note documented (advisory); drift-warn coverage acknowledged honestly in Phase 3 Design & Constraints; line-329 reconciliation has its own AC; py/cjs parity test concretized in WI 4.4.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 issues         | 10 issues                 | 22/22 (3 self-rejected by DA, 1 justified-with-mitigation, 18 fixed) |
| 2     | 6 issues          | 8 issues                  | 14/14 (3 self-rejected by DA after empirical check, 4 confirming/no-fix, 7 fixed) |
| 3     | 3 issues          | 9 issues                  | 12/12 (4 fixed, 5 justified-as-confirming on empirical check, 3 no-finding) |

## Disposition Table — Round 1 Adversarial Review

| # | Source | Finding (summary) | Evidence | Disposition |
|---|--------|-------------------|----------|-------------|
| R1, DA1 | Reviewer + DA | Regex `[^}]*` falsely captures from nested objects under `dev_server` | **Verified** — bash regex test (`/tmp/test-cfg-nested.json`): `[^}]*` captured `9999`, `[^{}]*` correctly returned no match | **Fixed**: Phase 2 WI 2.1 uses `[^{}]*`; Design & Constraints note explains; Out of Scope acknowledges existing `main_repo_path` block also vulnerable but not in scope |
| R2, DA2 | Reviewer + DA | WI code vs Design & Constraints contradicted on cfg-read refactor | **Verified** — original plan WI 1.3 had re-read code, D&C said "factor into single block" | **Fixed**: Phase 2 WI 2.1 explicitly specifies the refactor (move `unset` after both regexes; single read serves both); WI 2.2 addresses test-all.sh's local-scoped `_body` separately |
| R3 | Reviewer | AC `grep '8080' scripts/port.sh returns 0` ignores comment line 5 | **Verified** — port.sh:5 contains `# Main repo (...) -> 8080 (backward compatible).` | **Fixed**: Phase 2 WI 2.1 now also rewrites the header doc-comment; AC now uses `grep -nE '^[^#]*\b8080\b'` to match non-comment lines explicitly |
| R4 | Reviewer | WI ordering not enforced (could land 1.3 before 1.2) | Judgment | **Fixed**: phase-split (DA9 + R4 jointly) — Phase 1 only touches configs, Phase 2 only touches scripts, ordering is now structural |
| R5 | Reviewer | Phase 2 punted Option A vs B decision | Judgment + plan line 168 prose | **Fixed**: Phase 3 D&C now picks Option A explicitly with rationale; ACs collapse to single-arm |
| R6 | Reviewer | Phase 3 WI 3.3 same defer pattern (sync-check approach) | Judgment + plan lines 200-204 | **Fixed**: Phase 4 WI 4.3-4.4 now picks invariant-comment + parity-test approach explicitly |
| R7 | Reviewer | briefing comment lines mention 8080, not in WI | **Verified** — briefing.py:798, 803, 1109, 1114 have `# ... default 8080.` comments | **Fixed**: Phase 4 WI 4.1-4.2 now explicitly rewrites the surrounding comments |
| R8, DA5 | Reviewer + DA | WI 1.8 fixture mechanism unspecified | **Verified** — tests/test-port.sh uses `bash "$PORT_SCRIPT"` against live config; port.sh:16 honors `REPO_ROOT` env var | **Fixed**: Phase 2 WI 2.3 specifies `REPO_ROOT`+`PROJECT_ROOT`-based fixture under `/tmp/zskills-port-fixture` literal path; Round 2 found PROJECT_ROOT also needs override (see R2-1) |
| R9 | Reviewer | Backfill detail lacking (last-field placement) | Judgment + skills/update-zskills/SKILL.md:229-239 prose-only | **Fixed**: Phase 1 WI 1.4 now specifies "insert before closing brace (order-independent)" with full-block fallback for old configs |
| R10 | Reviewer | Mirror command needs "from worktree root" note | Judgment | **Fixed**: WIs 1.5, 3.4, 5.3 all specify "from the worktree root" |
| R11 | Reviewer | Phase 4 WI 4.1 wording defers | Judgment | **Fixed**: Phase 5 WI 5.1 specifies canonical replacement `localhost:<your-port>/...`, applied to all three sites |
| R12 | Reviewer | AC `diff` should be `diff -r` | **Verified** — `man diff`: directory diff non-recursive by default | **Fixed**: all directory-diff ACs now use `diff -rq` |
| DA3 | DA | drift-warn hook is field-agnostic; Option A mitigation claim too strong | **Verified** — hooks/warn-config-drift.sh:35 file-path-only match; warning text field-agnostic | **Fixed**: Phase 3 D&C now states the mitigation honestly; Out of Scope notes field-specific signals as future work; Round 2 found additional coverage hole (see R2-3) |
| DA4 | DA | Schema default ≠ install template; three-source-of-truth for `8080` | **Verified** — skills/update-zskills/SKILL.md:262-296 is literal JSON template; Step 0.5 step 3.5 backfill is prose-only | **Fixed**: Phase 1 D&C now acknowledges the three locations; Phase 1 ACs verify all three say `8080`; Out of Scope adds single-sourcing as future work |
| DA6 | DA | briefing.py has two URL emission patterns (separate-line vs inline) | Verified by DA at briefing.py:859-860 (inline) and 1133-1135 (separate-line) | **Fixed**: Phase 4 WI 4.1 now enumerates both sites with per-pattern skip logic |
| DA7 | DA | `cp -r` form is portable; attack vector 10 unfounded | Verified by DA via cp(1) semantics + reproducer | **Justified — REJECTED as DA self-rejected**. The mirror command form is portable across BSD and GNU; the PR #62 bug was a different shape |
| DA8 | DA | Transition story breaks for users running port.sh before /update-zskills | Judgment | **Justified-with-mitigation**. Phase 2 D&C explicitly acknowledges the transition cost; the loud-fail message is now specific (resolved config path + slash-command clarification per R2-2) |
| DA9 | DA | Phase 1 split inverted; should be configs-first then scripts | Judgment | **Fixed**: phase structure changed — Phase 1 (configs) → Phase 2 (scripts), 5 phases total |
| DA10 | DA | SCRIPTS_INTO_SKILLS mid-execution drift not addressed | Judgment | **Fixed**: Out of Scope note now reads "if SCRIPTS_INTO_SKILLS lands at any point — before OR between phases — pause and run /refine-plan; do not start a new phase without verifying file paths" |

## Disposition Table — Round 2 Adversarial Review

| # | Source | Finding (summary) | Evidence | Disposition |
|---|--------|-------------------|----------|-------------|
| R2-1, DA2-1 | Reviewer + DA | WI 2.3 fixture mechanism broken — `port.sh` ignores `PROJECT_ROOT` env var (recomputes from SCRIPT_DIR) | **Verified** — `PROJECT_ROOT=/tmp/da3b REPO_ROOT=/tmp/da3b bash /workspaces/zskills/scripts/port.sh` → trace shows `+ PROJECT_ROOT=/workspaces/zskills` (not env value), printed worktree hash 20136 instead of fixture port | **Fixed**: Phase 2 WI 2.1 now adds `PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"` env override (mirroring the existing `REPO_ROOT` override pattern). WI 2.2 mirrors for test-all.sh. New AC verifies the env override works |
| R2-2 | Reviewer | Loud-fail message under-specified ("Run /update-zskills" vague) | Judgment + skills/update-zskills/SKILL.md:16 (slash-command form) | **Fixed**: Phase 2 WI 2.1 message now includes the resolved absolute config path AND clarifies "/update-zskills is a Claude Code slash command, not a shell command." AC verifies stderr contains the absolute config path |
| R2-3 | Reviewer | Regex `[^{}]*` requires nested-object ordering constraint be documented | **Verified** — round 2 test showed both `[^}]*` and `[^{}]*` fail to match when nested object appears BEFORE default_port | **Fixed**: Phase 1 D&C adds the constraint explicitly: "if dev_server gains a nested object, default_port must appear in serialization order before the nested object; IDE JSON-key sorting may break this" |
| R2-4 | Reviewer | WI 1.4 backfill confirmed sound (no fix needed) | **Verified** — `/tmp/test-edit-pattern.sh`: append before closing brace produces valid JSON | **Justified — confirming**. WI 1.4 is robust; insert-before-closing-brace is order-independent. Refined wording in WI 1.4 to make this explicit |
| R2-5 | Reviewer | WI 4.1 "audit" wording acceptable but could enumerate | Verified — exactly 4 viewer_url sites total across briefing.py + .cjs | **Fixed**: Phase 4 WI 4.1 now enumerates all four sites by line number with per-site skip logic (combined with DA6 from round 1) |
| R2-6 | Reviewer | Phase 1 → 2 dependency correct (no fix needed) | Judgment | **Justified — confirming**. Dependency graph is sound |
| DA2-1 | DA | Same as R2-1 (broken fixture mechanism) | Same evidence as R2-1 | **Fixed (same as R2-1)** |
| DA2-2 | DA | Phase 3 misses `{{MAIN_REPO_PATH}}` placeholder mapping (silent unsubstituted bug) | **Verified** — skills/update-zskills/SKILL.md:321-329 mapping table missing `{{MAIN_REPO_PATH}}`; CLAUDE_TEMPLATE.md:13 already uses it | **Fixed**: Phase 3 WI 3.2 now adds BOTH `{{DEFAULT_PORT}}` AND `{{MAIN_REPO_PATH}}` rows. New AC verifies both are substituted |
| DA2-3 | DA | drift-warn hook only fires on Edit/Write tool calls; external edits bypass entirely (much bigger coverage hole than DA3 round 1 said) | **Verified** — `.claude/settings.json:30-51` matchers `Edit` and `Write` only; `hooks/warn-config-drift.sh:23-26` bails on other tool_name | **Fixed**: Phase 3 D&C now describes coverage honestly (~30% of edit paths covered; external edits bypass). Out of Scope adds "broaden drift detection to fire on any config-file mtime change (e.g. SessionStart hook)" |
| DA2-4 | DA | Phase 4 WI 4.1 audit-and-defer should enumerate (same as R2-5) | Same as R2-5 | **Fixed (same as R2-5)** |
| DA2-5 | DA | Phase 1→2 transition window: schema docs the field but Phase 2 hasn't shipped → consumer might edit and be surprised | Judgment | **Fixed**: Phase 1 D&C "Inter-phase window" note added; Phase 2 D&C "Inter-phase transition" note added; recommend documenting in CHANGELOG / release notes |
| DA2-6 | DA | WI 5.4 (CLAUDE.md:18 commented-out HTML aside) defer self-rejects | **Verified** — CLAUDE.md:18 is HTML comment in this repo's own CLAUDE.md, not rendered, not read by any tool | **Justified — REJECTED as DA self-rejected**. WI 5.4 removed entirely; CLAUDE.md:18 explicitly listed under Phase 5 D&C "What's out" |
| DA2-7 | DA | WI 1.4 ordering robust (DA self-rejects) | **Verified** — append-before-closing-brace is order-independent | **Justified — confirming**. No change needed |
| DA2-8 | DA | String-typed `"default_port": "8080"` doesn't match integer regex (DA self-rejects) | **Verified** — bash test: string-quoted value fails the `[0-9]+` match → fail-loud surfaces the typo | **Justified — confirming**. Phase 1 D&C now mentions this as a benefit of integer typing |

## Disposition Table — Round 3 Adversarial Review

| # | Source | Finding (summary) | Evidence | Disposition |
|---|--------|-------------------|----------|-------------|
| R3-R1 | Reviewer | `skills/update-zskills/SKILL.md:329` classifies `dev_server.main_repo_path` as runtime-read-only, conflicting with WI 3.2's install-substitution mapping addition | **Verified** — line 329 reads "Runtime-read fields (not install-filled): testing.unit_cmd, testing.full_cmd, ui.file_patterns, dev_server.main_repo_path" | **Fixed**: Phase 3 WI 3.4 reconciles — main_repo_path is BOTH runtime-read by scripts AND install-substituted in template prose. New AC added to Phase 3 |
| R3-R2 | Reviewer | "~30%" coverage figure for warn-config-drift is hand-picked, not measured | Judgment | **Fixed**: softened to "a minority of plausible edit paths — only those that flow through Claude Code's Edit or Write tool" |
| R3-R3 | Reviewer | CHANGELOG note is advisory but not a WI; could silently drop | Judgment + CHANGELOG.md exists at repo root | **Justified-as-advisory**: the prose stays as a recommendation rather than a WI; CHANGELOG entries are typically composed by the lander, not specced as work items in a plan. Refiner's call |
| R3-DA1 | DA | WI 2.2 PROJECT_ROOT override under-specified vs WI 2.1's literal patch | **Verified** — WI 2.1 had explicit replacement text; WI 2.2 said "prefix with `${PROJECT_ROOT:-...}`" leaving quoting and `local` declaration ambiguous | **Fixed**: WI 2.2 now gives the literal replacement: `project_root="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"`. Order-relative-to-`_cfg_root` documented |
| R3-DA2 | DA | `{{MAIN_REPO_PATH}}` substitution: paths with spaces | Judgment + skills/update-zskills/SKILL.md:596-608 (Step B is agent-driven prose) | **Justified-as-confirming**: agent-driven substitution handles paths with special characters; markdown-prose context doesn't require shell escaping. If Step B is ever mechanized to a sed one-liner, escaping must be added — that's a future refactor concern |
| R3-DA3 | DA | Backfill spec under compact JSON shape | **Verified** — empirical sed test: insert-before-closing-brace works on both compact and multi-line shapes when the dev_server block has exactly one inner closing brace | **Justified-as-confirming**: agent-driven backfill handles the discretion; same precedent as `commit.co_author` backfill |
| R3-DA4 | DA | Loud-fail message worktree confusion ("Open this repo in Claude Code") | **Verified** — message includes resolved absolute config path which disambiguates | **Justified-as-confirming**: the absolute path in the message is the disambiguation; user can navigate to that file's directory and run /update-zskills there |
| R3-DA5 | DA | CHANGELOG.md exists; advice is grounded | **Verified** — `/workspaces/zskills/CHANGELOG.md` exists | **No finding** — confirming |
| R3-DA6 | DA | WI 4.4 "normalization for language differences (etc.)" defers parity-test work | Judgment | **Fixed**: WI 4.4 now requires either (a) refactor briefing source so no language-specific literals reach stdout (preferred — byte-equivalent output), or (b) enumerate normalization rules concretely. "Etc." removed |
| R3-DA7 | DA | Schema integer-vs-string field-type heterogeneity | **Verified** — config/zskills-config.schema.json already has heterogeneous nested objects (execution: string+boolean+string+string; ci: boolean+integer) | **No finding** — confirming. Adding integer to dev_server is consistent with existing precedent |
| R3-DA8 | DA | Disposition table accuracy spot-check | Judgment | **No finding** — DA verified rounds 1 & 2 dispositions look defensible |
| R3-DA9 | DA | Plan Quality's "all addressed" wording could be misread as "all fixed" | Judgment | **Justified-as-confirming**: "addressed" includes confirmed-as-not-needing-fix, which is accurate. The Round History table breaks down resolutions by category for clarity |
