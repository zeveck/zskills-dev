---
title: Default Port Config — Schema-Driven, Runtime-Read
created: 2026-04-25
status: active
---

# Plan: Default Port Config — Schema-Driven, Runtime-Read

> **Landing mode: PR** -- This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

zskills hardcodes port `8080` in seven places (port.sh, test-all.sh, briefing.py, briefing.cjs, the rendered template prose, plus minor docs). Consumers running Django (8000), Rails (3000), Vite (5173), Next.js (3000), etc. get the wrong port reported and written into their `managed.md`. The only override today is the per-invocation `DEV_PORT` env var.

This plan eliminates the hardcoded value by making port a configurable schema field — `dev_server.default_port`, integer, schema default `8080`. `/update-zskills` writes the field on greenfield install and backfills it into existing configs (mirroring the established `commit.co_author` backfill pattern). The runtime consumers (`port.sh`, `test-all.sh`) read the field via the canonical bash-regex pattern landed in DRIFT_ARCH_FIX Phase 1, with the scope-bound tightened to `[^{}]*` to be safe under future nested-object additions; no code-level fallback. `briefing.py` and `briefing.cjs` drop their literal `'8080'` and gracefully omit URLs when port determination fails.

The plan is split into 5 phases. Phase 1 lands the field (schema + this-repo config + /update-zskills writes/backfills) so that consumers running `/update-zskills` after pulling will have the field present before any later phase needs it. Phase 2 then migrates `port.sh` and `test-all.sh` to read the field and adds a `PROJECT_ROOT` env override so that test fixtures can isolate the script from this repo's own config. The renderer, drift-warn hook, and pattern are all already landed from DRIFT_ARCH_FIX.

> **Refine note (2026-04-29):** WIs 1.1-1.3 were inline-absorbed by SCRIPTS_INTO_SKILLS Phase 3a (PR #97); WI 2.2 became obsolete via CONSUMER_STUB_CALLOUTS' test-all.sh stub conversion (PRs #105/#106); WI 2.1 partially landed with deviations. See Drift Log for full reconciliation. Substantive remaining work: port.sh tightening + fail-loud (Phase 2), CHANGELOG correction + port_script template cleanup (Phase P1.A), template prose refinement + placeholder mapping bug fix (Phase 3), briefing path-fix + literal removal (Phase 4), doc surfaces (Phase 5).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 2 — port.sh runtime-read tightening + fail-loud + fixture isolation | 🟡 | `cbccfe1` | tightened regex + fail-loud + 3 fixture cases; +3 tests |
| P1.A — CHANGELOG correction + greenfield port_script template removal | 🟡 | `b66bbc5` | CHANGELOG fixed + greenfield template port_script removed; +0/-0 tests |
| 3 — Template prose refinement + Step B placeholder mapping | 🟡 | `f85a546` | {{DEFAULT_PORT}} + {{MAIN_REPO_PATH}} substitution; conformance test reconciled; +6 tests |
| 4 — briefing.py / briefing.cjs path-fix + drop literal + omit-URL on failure | ⬚ | | |
| 5 — Documentation surfaces | ⬚ | | |

---

## Phase 2 — `port.sh` runtime-read tightening + fail-loud + fixture isolation

### Goal

Tighten the partially-landed runtime-read in `skills/update-zskills/scripts/port.sh`: replace the loose regex scope-bound with `[^{}]*` to refuse traversal of nested objects, remove the literal `DEFAULT_PORT=8080` fallback, and replace the `git rev-parse --show-toplevel` PROJECT_ROOT derivation with the `${PROJECT_ROOT:-...}`-style env override required for fixture-based testing. Add a fail-loud message that fires only when the field is genuinely absent AND the consumer dev-port.sh stub did not produce output (the stub's empty-stdout silent fall-through must remain intact). Update `tests/test-port.sh` to assert the new behavior with literal-path fixtures under `/tmp/`.

### Work Items

- [ ] 2.1 — Tighten `skills/update-zskills/scripts/port.sh` regex scope-bound. Current line 38 reads:
  ```bash
  if [[ "$_ZSK_CFG_BODY" =~ \"dev_server\"[[:space:]]*:[[:space:]]*\{[^}]*\"default_port\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
  ```
  Replace `[^}]*` with `[^{}]*`. The tightened pattern refuses to traverse a nested object inside `dev_server`. (Verified in the prior plan rounds: `[^}]*` falsely captures `9999` from `{"dev_server": {"limits": {"default_port": 9999}, "default_port": 3000}}`; `[^{}]*` correctly returns no match in that pathological shape.)

- [ ] 2.2 — Add a `PROJECT_ROOT` env override at port.sh:18. Current line reads:
  ```bash
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  ```
  Replace with:
  ```bash
  PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  ```
  This mirrors the existing `REPO_ROOT` env override at line 28 and is required for fixture-based testing in WI 2.5. The git-toplevel fallback (introduced after the script moved into the skill bundle — see header comment at port.sh:12-17) is preserved when the env var is unset.

- [ ] 2.3 — Remove the literal `DEFAULT_PORT=8080` fallback at port.sh:20 and add fail-loud-when-missing logic. Current shape:
  ```bash
  DEFAULT_PORT=8080  # fallback when config field is absent
  ```
  Change to:
  ```bash
  DEFAULT_PORT=""
  ```
  Then, in the "Main repo gets the default port" branch at port.sh:80-83, replace:
  ```bash
  if [[ -n "$MAIN_REPO" ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
    echo "$DEFAULT_PORT"
    exit 0
  fi
  ```
  with a fail-loud guard that runs ONLY in the main-repo branch (worktrees compute their port from the path hash and never need `DEFAULT_PORT`):
  ```bash
  if [[ -n "$MAIN_REPO" ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
    if [[ -z "$DEFAULT_PORT" ]]; then
      echo "port.sh: dev_server.default_port not set in $_ZSK_CFG. Open this repo in Claude Code and run /update-zskills (a Claude Code slash command, not a shell command) to backfill the field, or set DEV_PORT=NNNN env var to override per-invocation." >&2
      exit 1
    fi
    echo "$DEFAULT_PORT"
    exit 0
  fi
  ```
  Note: `_ZSK_CFG` is currently `unset` at port.sh:43 before the main-repo branch. **Move the `unset _ZSK_REPO_ROOT _ZSK_CFG` line to AFTER the main-repo branch exit** so the fail-loud message can reference the resolved absolute config path. Equivalently: keep `_ZSK_CFG` alive until after the only place that can use it.

- [ ] 2.4 — **Stub-callout precedence — keep silent fall-through intact.** The fail-loud check from WI 2.3 fires inside the "Main repo gets the default port" branch (port.sh:80). Verify the control flow:
  1. Lines 46-49: `DEV_PORT` env var — wins, exits if set.
  2. Lines 51-77: Consumer `dev-port.sh` stub callout. If it returns a valid port → exit 0 with that port. If it returns empty stdout → silent fall-through (per stub-callout contract); a warning is emitted only on non-numeric/invalid stdout (port.sh:67-69).
  3. Lines 80-83: Main-repo branch — this is where WI 2.3's fail-loud check runs.
  4. Lines 85-89: Worktree-hash branch.
  Because the fail-loud only fires when (a) DEV_PORT is unset AND (b) the stub callout did not exit with a port AND (c) `MAIN_REPO` is set AND (d) `PROJECT_ROOT == MAIN_REPO` AND (e) `DEFAULT_PORT` is empty, it strictly does NOT interfere with the stub's "empty stdout = silent fall-through" contract: silent fall-through proceeds to the main-repo or worktree branch as before. The fail-loud only fires in the truly-pathological case where `default_port` was deleted from the config AND the consumer is at the main repo AND no stub override is configured. This is the correct semantics per the plan's Overview ("no code-level fallback") AND the stub's contract ("empty stdout means built-in algorithm runs").
  No code change in this WI — it documents the verified precedence chain in port.sh's header doc-comment (port.sh:1-9). Append two lines to the comment block:
  ```
  # Precedence: DEV_PORT env -> dev-port.sh stub (consumer-provided) ->
  # dev_server.default_port (main-repo branch; fail-loud if absent) -> worktree-hash.
  ```

- [ ] 2.5 — Update `tests/test-port.sh` to add fixture-based cases. The existing tests for determinism, DEV_PORT override, range, and numeric output (lines 22-60) are unchanged. The existing "could be 8080 if MAIN_REPO matches" branch at lines 47-49, 95, 98, 121, 136, 154 needs auditing (some of those references use the worktree-hash-OR-8080 disjunction as a "tolerate either" assertion — keep the disjunction but verify the literal `"8080"` stays valid against this repo's own config which has `default_port: 8080`).
  Add three NEW test cases after the existing ones:
  - **Fixture with `default_port: 7777`** (verifies PROJECT_ROOT override + configured value):
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
  - **Fixture WITHOUT `default_port` field** (verifies fail-loud):
    ```bash
    FIXTURE=/tmp/zskills-port-fixture-absent
    rm -rf "$FIXTURE" && mkdir -p "$FIXTURE/.claude"
    cat > "$FIXTURE/.claude/zskills-config.json" <<JSON
    {"dev_server": {"main_repo_path": "$FIXTURE"}}
    JSON
    err=$(REPO_ROOT="$FIXTURE" PROJECT_ROOT="$FIXTURE" bash "$PORT_SCRIPT" 2>&1 >/dev/null)
    rc=$?
    [[ $rc -ne 0 ]] || fail "fail-loud expected non-zero exit, got $rc"
    [[ "$err" == *"default_port"* ]] || fail "fail-loud stderr missing 'default_port'"
    [[ "$err" == *"$FIXTURE/.claude/zskills-config.json"* ]] || fail "fail-loud stderr missing absolute config path"
    rm -rf "$FIXTURE"
    ```
  - **Fixture with nested object before `default_port`** (verifies tightened regex refuses traversal):
    ```bash
    FIXTURE=/tmp/zskills-port-fixture-nested
    rm -rf "$FIXTURE" && mkdir -p "$FIXTURE/.claude"
    cat > "$FIXTURE/.claude/zskills-config.json" <<JSON
    {"dev_server": {"limits": {"default_port": 9999}, "main_repo_path": "$FIXTURE"}}
    JSON
    # default_port appears only inside nested "limits" object → tight regex must NOT match
    err=$(REPO_ROOT="$FIXTURE" PROJECT_ROOT="$FIXTURE" bash "$PORT_SCRIPT" 2>&1 >/dev/null)
    rc=$?
    [[ $rc -ne 0 ]] || fail "tight-regex test expected fail-loud (nested-only default_port should NOT match)"
    rm -rf "$FIXTURE"
    ```
  All three fixture paths are literal `/tmp/zskills-port-fixture*` strings (per safety-hook policy).

- [ ] 2.6 — Mirror the source-skill edit to `.claude/skills/update-zskills/scripts/port.sh`. From the worktree root:
  ```bash
  bash scripts/mirror-skill.sh update-zskills
  ```
  This invokes `scripts/mirror-skill.sh` (PR #88), which uses per-file rm under the hood and is hook-compatible. Inline `rm -rf .claude/skills/X && cp -r ...` snippets are blocked by `hooks/block-unsafe-generic.sh` (verified during refinement: a grep against the hook fired the block).

### Design & Constraints

**Why ratify the partial landing's `git rev-parse` derivation but tighten everything else.** The intervening landing (port.sh moved into `skills/update-zskills/scripts/`) made the original `cd "$SCRIPT_DIR/.." && pwd` approach broken — `$SCRIPT_DIR/..` now points inside the skill bundle, not the consumer repo root. The header comment at port.sh:12-17 documents this. The `git rev-parse --show-toplevel` derivation is correct for the consumer-repo case AND testable when paired with the new `${PROJECT_ROOT:-...}` env override. Tightening to `${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}` preserves the correct derivation while admitting fixture overrides. The original plan's `${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}` literal cannot work given the new script location.

**Why fail-loud only in the main-repo branch.** Worktrees do NOT use `DEFAULT_PORT` — they compute from the path hash regardless. Failing loud globally on absent `default_port` would break worktrees in any consumer that hasn't yet run `/update-zskills` to backfill the field. Scoping the check to the main-repo branch confines the failure to where the field is actually needed.

**`test-all.sh` does not need a refactor.** It's a 17-line failing stub that prints "test-all.sh: not configured" to stderr and exits 1. The original Phase 2 WI 2.2 patched a `get_port()` function that no longer exists in the file. Stripping the WI is correct; the stub-callout convention shipped (PRs #105/#106) is what governs the new contract, and consumers' replacement test-all.sh implementations are out-of-scope (each consumer writes their own).

**Tighter regex scope-bound for default_port; existing main_repo_path block left loose.** The `main_repo_path` regex at port.sh:34 still uses `[^}]*`. Tightening it to `[^{}]*` is theoretically the same fix but lower-risk (string field, no nested-object precedent). Tracked in Out of Scope as a sweep candidate.

**Acknowledged inter-phase window.** Between this phase landing and Phase 4 landing, briefing.{py,cjs} continue to look for port.sh at the wrong path AND fall back to literal `'8080'`. That's the bug Phase 4 fixes. CHANGELOG entry should describe the full sequence when shipped.

### Acceptance Criteria

- [ ] `grep -nE '\[\^\}\]\*"default_port"' skills/update-zskills/scripts/port.sh` returns no matches (the loose pattern is replaced).
- [ ] `grep -nE '\[\^\{\}\]\*"default_port"' skills/update-zskills/scripts/port.sh` matches at exactly one site (port.sh:38 area).
- [ ] `grep -nE 'PROJECT_ROOT="\$\{PROJECT_ROOT:-' skills/update-zskills/scripts/port.sh` matches at port.sh:18.
- [ ] `grep -nE '^DEFAULT_PORT=8080' skills/update-zskills/scripts/port.sh` returns no matches (literal default removed).
- [ ] `bash skills/update-zskills/scripts/port.sh` from this repo's root prints `8080` (the configured default in this repo's `.claude/zskills-config.json`).
- [ ] In a fixture config with `"default_port": 7777`, `REPO_ROOT=<fixture> PROJECT_ROOT=<fixture> bash skills/update-zskills/scripts/port.sh` prints `7777`.
- [ ] In a fixture config without `default_port`, `REPO_ROOT=<fixture> PROJECT_ROOT=<fixture> bash skills/update-zskills/scripts/port.sh` exits non-zero AND stderr contains `default_port` AND stderr contains the absolute config path.
- [ ] In a fixture config with `default_port` only inside a nested object, the script exits non-zero (tight regex refuses traversal).
- [ ] `tests/test-port.sh` includes the three new fixture-based cases, all passing.
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (LANDED — schema field + this-repo config + greenfield template). No remaining Phase 1 work blocks this phase except WI P1.A (CHANGELOG correction or backfill, see below) which can land in parallel.

## Phase P1.A — CHANGELOG correction OR backfill implementation (residual Phase 1 work)

### Goal

Reconcile the CHANGELOG.md aspirational claim with shipped reality. **Decision: CORRECT THE CHANGELOG** (do NOT implement default_port backfill in this plan). Rationale below.

### Work Items

- [ ] P1.A.1 — Edit `CHANGELOG.md` lines 85-91. Current entry claims "/update-zskills writes `default_port` on greenfield install AND backfills it into existing configs." The greenfield-write part is true (`skills/update-zskills/SKILL.md:281`); the backfill claim is aspirational (verified — `grep -n "default_port" skills/update-zskills/SKILL.md` shows zero hits in the backfill block at lines 226-236, only the `co_author` backfill exists there). Update the entry to reflect what shipped:
  > feat(config): drop dev_server.port_script (port.sh now lives in update-zskills skill); add dev_server.default_port for main-repo port override
  >   — `port.sh` is now bundled with the `update-zskills` skill at one
  >   canonical location; the `port_script` config field that pointed at
  >   it is removed. `dev_server.default_port` (integer, default 8080)
  >   added so the main-repo port is configurable. `/update-zskills`
  >   writes `default_port` on greenfield install. Existing configs
  >   without the field will receive a fail-loud diagnostic from port.sh
  >   (run `/update-zskills` to add the field manually for now; automatic
  >   backfill is tracked as future work).

- [ ] P1.A.2 — Edit `skills/update-zskills/SKILL.md:282` to remove the `"port_script": ""` greenfield-template remnant. Current shape:
  ```json
  "dev_server": {
    "cmd": "<detected>",
    "default_port": 8080,
    "port_script": "",
    "main_repo_path": "<detected>"
  },
  ```
  Becomes:
  ```json
  "dev_server": {
    "cmd": "<detected>",
    "default_port": 8080,
    "main_repo_path": "<detected>"
  },
  ```
  The `port_script` field is no longer in the schema (verified — `grep port_script config/zskills-config.schema.json` returns nothing). The current code writes it on greenfield then strips it at SKILL.md:1075-1088 — needless work. Strip the writer; keep the stripper (the stripper is still needed for existing consumer configs that have the field carried over from old installs).

- [ ] P1.A.3 — Mirror to `.claude/skills/update-zskills/SKILL.md`:
  ```bash
  bash scripts/mirror-skill.sh update-zskills
  ```

### Design & Constraints

**Why correct CHANGELOG instead of implementing backfill.** Implementing default_port backfill is a non-trivial sub-WI: it requires detecting whether the existing config has a `dev_server` block, whether that block has `default_port`, and inserting the field idempotently — exactly the work that was originally specced as Phase 1 WI 1.4. With the fail-loud message from Phase 2 WI 2.3 explicitly directing users to run `/update-zskills`, the consumer experience for an unbacked-filled config is: (a) port.sh fails loud with the absolute config path, (b) the user runs `/update-zskills`, which today does NOT add the field but rewrites the schema link. Aspirational backfill remains a real follow-up — but in the current refactor scope (port.sh tightening + briefing path fix + template prose + docs sweep), claiming "backfill ships" in CHANGELOG when it doesn't is a worse defect than honest documentation of the actual state. Capturing the gap in CHANGELOG and Out of Scope is the right resolution.

**Why include greenfield-template `port_script` cleanup.** The template writing `"port_script": ""` then immediately stripping it (SKILL.md:1075-1088) is incoherent given the schema no longer has the field. Closing this gap removes a confusing artifact and is one-line touch.

### Acceptance Criteria

- [ ] `CHANGELOG.md` entry no longer claims backfill ships. Verify: `grep -E 'backfill.*default_port|default_port.*backfill' CHANGELOG.md` returns no matches in active prose (or matches only future-work language).
- [ ] `grep -nE '"port_script"' skills/update-zskills/SKILL.md` matches only the strip-legacy code block (line 1080-area), NOT the greenfield template (line 282 area).
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

None. Can land in parallel with Phase 2.

## Phase 3 — Template prose refinement + Step B placeholder mapping

### Goal

Refine `CLAUDE_TEMPLATE.md:22` (the rewritten dev-server prose) to be honest about port determination given that the dev-port.sh stub callout can return any port. Add the missing `{{MAIN_REPO_PATH}}` placeholder mapping (active silent-unsubstituted bug — verified: `{{MAIN_REPO_PATH}}` appears in the template prose at line 22 but not in the SKILL.md placeholder mapping table at lines 321-324). Reconcile SKILL.md:326's "runtime-read fields" classification.

### Work Items

- [ ] 3.1 — Edit `CLAUDE_TEMPLATE.md:22`. Current line:
  > The port is determined automatically (8080 for the main repo `{{MAIN_REPO_PATH}}`; a deterministic per-worktree port otherwise). Run `bash .claude/skills/update-zskills/scripts/port.sh` to see your port. Override with `DEV_PORT=NNNN` env var, or with a `scripts/dev-port.sh` stub for project-wide custom logic (see `.claude/skills/update-zskills/references/stub-callouts.md`).
  
  Becomes:
  > The port is determined automatically: by default `{{DEFAULT_PORT}}` for the main repo `{{MAIN_REPO_PATH}}`, and a deterministic per-worktree port otherwise. If a `scripts/dev-port.sh` consumer stub is present, it overrides the default for the main repo. Run `bash .claude/skills/update-zskills/scripts/port.sh` to see your actual port. Override per-invocation with `DEV_PORT=NNNN`. See `.claude/skills/update-zskills/references/stub-callouts.md` for the stub contract.
  
  Substitution choice rationale: with the dev-port.sh stub now in the precedence chain, displaying a literal `**8080**` would actively LIE whenever the stub returns a different value (which the stub is explicitly designed to do — that's its whole purpose). The "by default" qualifier with the stub-override caveat is honest about both the configured-default substitution AND the runtime-overridable layer above it. The "Run `bash …port.sh` to see your actual port" sentence remains as the canonical way to discover the live value.

- [ ] 3.2 — Edit `skills/update-zskills/SKILL.md:319-324` (the placeholder mapping table). Add TWO rows so the table reads:
  ```
  | Placeholder | Config path | Example |
  |-------------|-------------|---------|
  | `{{DEV_SERVER_CMD}}` | `dev_server.cmd` | `npm start` |
  | `{{AUTH_BYPASS}}` | `ui.auth_bypass` | `localStorage.setItem(...)` |
  | `{{DEFAULT_PORT}}` | `dev_server.default_port` | `8080` |
  | `{{MAIN_REPO_PATH}}` | `dev_server.main_repo_path` | `/path/to/repo` |
  ```
  The `{{MAIN_REPO_PATH}}` row is a **bug fix**: that placeholder is already used in `CLAUDE_TEMPLATE.md:22` but missing from the substitution mapping today, so consumer renders contain a literal `{{MAIN_REPO_PATH}}` substring (active shipping bug per /refine-plan instruction item 6). The `MAIN_REPO_PATH` variable is already extracted at SKILL.md:189-191 — adding the mapping row is what wires the extraction to substitution.

- [ ] 3.3 — Verify Step B's substitution logic at SKILL.md:596-607 will substitute the two new placeholders. The substitution is described as "Placeholder mapping is documented in Step 0.5" (line 600). Step B is agent-driven prose; the agent reads each `{{PLACEHOLDER}}` from the template and substitutes from the corresponding config field. Adding rows to the mapping table at Step 0.5 is therefore the only required change. No further code edit needed in Step B itself; the agent following the prose will pick up the new rows.
  
  Validation: this WI is documentation-and-mapping-only. The actual integer-vs-string distinction (`{{DEFAULT_PORT}}` substitutes digits without surrounding quotes since it's in markdown prose, not JSON) is implicit in the agent-driven render — markdown prose receives the value as-rendered.

- [ ] 3.4 — Reconcile `skills/update-zskills/SKILL.md:326`. Current line:
  > Runtime-read fields (not install-filled): `testing.unit_cmd`, `testing.full_cmd`, `ui.file_patterns`, `dev_server.main_repo_path`. Hooks and helper scripts read these directly from `.claude/zskills-config.json` at every invocation — see Phase 1 of `plans/DRIFT_ARCH_FIX.md`.
  
  This conflicts with WI 3.2 adding `{{MAIN_REPO_PATH}}` to the install-substitution mapping. Replacement:
  > Runtime-read fields (read by hooks and helper scripts at every invocation, NOT install-filled): `testing.unit_cmd`, `testing.full_cmd`, `ui.file_patterns`. The field `dev_server.main_repo_path` is read at runtime by `port.sh` AND install-substituted into managed.md as `{{MAIN_REPO_PATH}}` (the rendered value reflects the config at install/--rerender time; warn-config-drift signals re-render-needed when the config is edited via Claude Code's Edit/Write tool — see Phase 3 Design & Constraints for coverage limits). Similarly, `dev_server.default_port` is runtime-read by `port.sh` AND install-substituted as `{{DEFAULT_PORT}}`. See Phase 1 of `plans/DRIFT_ARCH_FIX.md` for the canonical bash-regex read pattern.

- [ ] 3.5 — Mirror to `.claude/skills/update-zskills/SKILL.md` and `.claude/CLAUDE_TEMPLATE.md`. From the worktree root:
  ```bash
  bash scripts/mirror-skill.sh update-zskills
  cp CLAUDE_TEMPLATE.md .claude/CLAUDE_TEMPLATE.md  # (only if .claude/CLAUDE_TEMPLATE.md exists; verify before copy)
  ```
  Note: `CLAUDE_TEMPLATE.md` is at the repo root, not inside a skill. The mirror-skill.sh helper does NOT cover it; if there's a `.claude/CLAUDE_TEMPLATE.md` in this repo, the cp step keeps them in sync. Verify both exist before copying:
  ```bash
  if [ -f .claude/CLAUDE_TEMPLATE.md ]; then cp CLAUDE_TEMPLATE.md .claude/CLAUDE_TEMPLATE.md; fi
  ```

- [ ] 3.6 — Update `tests/test-update-zskills-rerender.sh` (or the equivalent test surface — `grep -l 'rerender\|managed.md' tests/*.sh` shows `tests/test-update-zskills-migration.sh` exists; pick the file that already covers the substitution path) to assert:
  - A fresh install with `default_port: 8080` produces `managed.md` whose Architecture section's port line contains the literal `8080` (substituted from `{{DEFAULT_PORT}}`).
  - Editing the config to `default_port: 3000` and running `/update-zskills --rerender` produces `managed.md` containing `3000` in that line.
  - `{{MAIN_REPO_PATH}}` is fully substituted (no leftover `{{MAIN_REPO_PATH}}` substring in rendered file).
  - The rendered `managed.md` contains no leftover `{{DEFAULT_PORT}}` or `{{MAIN_REPO_PATH}}` placeholder.
  
  If `tests/test-update-zskills-rerender.sh` does not exist (verified at refinement time — only `tests/test-update-zskills-migration.sh` is present), create it new. Use the standard `pass`/`fail` test scaffolding from `tests/test-port.sh:12-20`.

### Design & Constraints

**Decision rationale (placeholder substitution vs generic prose).** Substitution wins because `{{MAIN_REPO_PATH}}` is already in the template — leaving the rest generic while substituting `MAIN_REPO_PATH` is asymmetric. With the dev-port.sh stub now in the picture, the prose is honest about the layered determination ("by default X; the stub overrides; run port.sh to see actual"). Consumers reading their managed.md still see a concrete number when the default applies; the qualifier handles the stub-override case without lying.

**Drift risk and its mitigation — honest scope.** `hooks/warn-config-drift.sh` fires only on `Edit` and `Write` PostToolUse matchers (`.claude/settings.json:30-51`). External edits — IDE, `git pull`, `sed`-via-Bash, `gh secret set`, CI workflow edits — bypass the hook entirely. Substitution is therefore a real-but-incomplete drift backstop. We accept this because (a) the UX win is real (concrete default on the page), (b) the "Run `bash …port.sh` to see your actual port" sentence is the canonical authoritative read-path that's drift-immune, and (c) field-aware drift detection (e.g., a SessionStart hook hashing the config) is a separate enhancement (see Out of Scope).

**Step B is agent-driven, not mechanized.** The substitution prose at SKILL.md:596-607 directs the running agent to substitute `{{PLACEHOLDER}}` strings using the mapping table. This is intentional — paths with spaces, quotes, special characters are handled by the agent's prose-context judgment. If Step B is ever mechanized to a sed one-liner, escaping rules must be added (out of scope).

### Acceptance Criteria

- [ ] `grep -c '8080' CLAUDE_TEMPLATE.md` returns 0 (literal removed; `{{DEFAULT_PORT}}` substitutes).
- [ ] `grep -c '{{DEFAULT_PORT}}' CLAUDE_TEMPLATE.md` returns 1 (the new placeholder).
- [ ] `grep -c '{{MAIN_REPO_PATH}}' CLAUDE_TEMPLATE.md` returns 1 (already present, unchanged).
- [ ] `skills/update-zskills/SKILL.md` placeholder mapping table includes both `{{DEFAULT_PORT}}` AND `{{MAIN_REPO_PATH}}` rows. Verify: `grep -E '\{\{(DEFAULT_PORT|MAIN_REPO_PATH)\}\}' skills/update-zskills/SKILL.md` matches both.
- [ ] `skills/update-zskills/SKILL.md` line 326 (or wherever the runtime-read prose lives after WI 3.4) no longer classifies `dev_server.main_repo_path` as runtime-read-only; explicitly notes the dual role.
- [ ] `diff -rq skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] In a sandbox fixture install at `/tmp/zskills-render-fixture` with `default_port: 3000`, the rendered `managed.md` contains `3000` in the Architecture port line and no `{{DEFAULT_PORT}}` substring.
- [ ] After editing the fixture config to `default_port: 5173` and re-rendering, `managed.md` contains `5173` in the Architecture port line.
- [ ] In the same fixture, `{{MAIN_REPO_PATH}}` is fully substituted (no `{{MAIN_REPO_PATH}}` substring in the rendered file).
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (LANDED — the schema field and consumer-config presence is what the placeholder substitutes from).

## Phase 4 — `briefing.py` / `briefing.cjs` path-fix + drop literal + omit-URL on failure

### Goal

Fix the briefing scripts' silently-broken port.sh path lookup BEFORE removing the `'8080'` literal fallback. The current code constructs `os.path.join(main_path, 'scripts', 'port.sh')` (Python) and `path.join(mainPath, 'scripts', 'port.sh')` (Node), but port.sh has moved to `skills/update-zskills/scripts/port.sh` (verified — `find . -name port.sh` returns only `skills/update-zskills/scripts/port.sh`). The path lookup fails today, the script falls through to the literal fallback, and the rendered briefing reports show `localhost:8080/...` URLs unconditionally. Once the path is fixed, drop the literal and gracefully omit URLs when port.sh truly errors.

### Work Items

- [ ] 4.0 — **Fix the port.sh path lookup BEFORE touching the fallback.** This must land first; otherwise removing the fallback strictly degrades the consumer experience. The fix:
  - In `skills/briefing/scripts/briefing.py:803` and `:1114`, replace:
    ```python
    port_sh = os.path.join(main_path, 'scripts', 'port.sh')
    ```
    with:
    ```python
    port_sh = os.path.join(main_path, '.claude', 'skills', 'update-zskills', 'scripts', 'port.sh')
    ```
  - In `skills/briefing/scripts/briefing.cjs:708` and `:1082`, replace:
    ```js
    const portSh = path.join(mainPath, 'scripts', 'port.sh');
    ```
    with:
    ```js
    const portSh = path.join(mainPath, '.claude', 'skills', 'update-zskills', 'scripts', 'port.sh');
    ```
  - Verify both files use the consumer's `.claude/skills/...` mirror path (which is the canonical location for installed-skill scripts; see CLAUDE.md "Architecture" — skills/ is source, .claude/skills/ is the installed copy that other tooling reads). The briefing scripts run inside the consumer's main repo, so `mainPath/.claude/skills/...` is the correct lookup.

- [ ] 4.1 — **Now drop the `'8080'` literal fallback** in `skills/briefing/scripts/briefing.py`. Four sites verified by grep against current file:
  - **Inline-URL site, briefing.py:861-862** (pattern `lines.append(f' {topic} ({len(items)}) — {viewer_url}')`): when `port` is `None`, emit the line WITHOUT the `— {viewer_url}` suffix (i.e., `lines.append(f' {topic} ({len(items)})')`).
  - **Separate-line URL site, briefing.py:1135-1137** (pattern `lines.append(f' {viewer_url}')` as its own line): when `port` is `None`, skip this `lines.append` call entirely.
  - **Port-fallback site, briefing.py:800-807**: remove the `port = '8080'` initializer at line 801; remove the `or '8080'` fallback after the `run(...)` call at line 805. When port.sh path doesn't exist OR `run()` returns empty/raises, set `port = None`.
  - **Port-fallback site, briefing.py:1111-1117**: same edits at lines 1112, 1116.
  - Rewrite the surrounding comments at lines 800 and 1111 (`# Get port for localhost URLs via port.sh; default 8080.` → `# Get port via port.sh; emit no URL on failure.`).

- [ ] 4.2 — Apply the equivalent edits to `skills/briefing/scripts/briefing.cjs`. Four sites verified:
  - **Inline-URL site, briefing.cjs:782** (`const viewerUrl = ...; lines.push(...)`): when `port` is `null`, emit the line without the URL suffix.
  - **Separate-line URL site, briefing.cjs:1101-1103** (`const viewerUrl = ...; lines.push(viewerUrl)`): when `port` is `null`, skip the push.
  - **Port-fallback site, briefing.cjs:705-712**: remove `let port = '8080';` at line 706; remove `|| '8080'` at line 710; the `catch` block at line 712 should set `port = null`.
  - **Port-fallback site, briefing.cjs:1079-1086**: same edits at lines 1080, 1084, 1086.
  - Rewrite the surrounding comments at lines 705 and 1079 (`// Get port for localhost URL via port.sh; default 8080.` → `// Get port via port.sh; emit no URL on failure.`).

- [ ] 4.3 — Add a one-paragraph py/cjs invariant comment at the top of both `skills/briefing/scripts/briefing.py` and `skills/briefing/scripts/briefing.cjs` (after the existing module docstring/header but before the imports). Wording:
  ```
  # ZSKILLS INVARIANT: briefing.py and briefing.cjs are intentional Python/Node mirrors.
  # Their port-handling behavior, output structure, and degradation semantics MUST stay byte-equivalent
  # except for language idioms (`'` vs `"`, `None` vs `null`, comment syntax). Edits to one require
  # a parity edit to the other. tests/test-briefing-parity.sh enforces this.
  ```
  Use comment syntax appropriate to each language (`#` for Python, `//` for JS).

- [ ] 4.4 — Extend `tests/test-briefing-parity.sh` (which already exists; 152 lines verified at refinement time) with port-failure parity cases:
  - Use a fixture that ensures port.sh's path-resolved location does NOT exist (set `main_path` to a directory without `.claude/skills/update-zskills/scripts/port.sh`). Literal path: `/tmp/zskills-briefing-fixture-noport`.
  - Run briefing.py and briefing.cjs against the fixture using the existing parity-test harness pattern (the test already builds `node_summary` and `py_summary` strings).
  - Assert: neither emits a `localhost:` URL (`grep -c 'localhost:' "$out"` returns 0 for both).
  - Assert: both run to completion (exit 0; no exception/crash).
  - Assert: both produce equivalent output. Implementation: first run `grep -nE '\\b(None|null|True|False|true|false)\\b' skills/briefing/scripts/briefing.{py,cjs}` to enumerate language-specific literals that could leak into stdout. If the grep finds any in code paths that touch stdout, refactor the source so language-specific literals do NOT reach stdout (preferred — both implementations should emit equivalent text). If refactor is impractical, document the specific normalization rules (e.g., `s/None/null/g`) and apply them before the diff. Do NOT use vague "normalize for language differences" as the test spec.

- [ ] 4.5 — Mirror to `.claude/skills/briefing/`:
  ```bash
  bash scripts/mirror-skill.sh briefing
  ```

### Design & Constraints

**WI 4.0 ordering: path fix BEFORE fallback removal.** Today the fallback masks a path-lookup bug — removing the fallback first would cause every briefing report to emit URLs only after WI 4.0 lands AND the fallback is removed; the intermediate state (fallback removed, path still wrong) would emit zero URLs everywhere. WI 4.0 lands first, restoring the URL-emission for the common case; then WI 4.1/4.2 drop the fallback, refining the failure-mode behavior. The two are sequenced within the same phase but the work-item ordering is load-bearing.

**Why `.claude/skills/update-zskills/scripts/port.sh` and not `skills/update-zskills/scripts/port.sh`.** Briefing runs in the consumer's main repo. `.claude/skills/` is the installed-skill location consumed by other tooling (per CLAUDE.md "Architecture": "`.claude/skills/` — installed skill copies (what Claude Code reads)"). Using `.claude/skills/...` is consistent with how `manual-testing/SKILL.md:25` and `briefing/SKILL.md:128-129` already invoke port.sh (verified — both reference `bash "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/port.sh"`).

**Why drop the fallback entirely.** With Phase 1's `default_port` field schema-defaulted to 8080 AND port.sh emitting fail-loud-with-config-path on absent field (Phase 2 WI 2.3), port.sh failure in steady state is the pathological case. A briefing literal `'8080'` masking the underlying issue keeps consumers in the dark.

**Why omit the URL rather than substitute a placeholder.** A URL with a wrong port is worse than no URL — users will click and get connection-refused. Better to indicate "port unavailable" by silence.

**py/cjs sync.** WI 4.3 (invariant comment) and WI 4.4 (parity test extension) make sync a checkable invariant — and the existing `tests/test-briefing-parity.sh` already enforces structural parity at the JSON-keys level. WI 4.4 extends it to port-failure semantics.

### Acceptance Criteria

- [ ] `grep -c '8080' skills/briefing/scripts/briefing.py` returns 0.
- [ ] `grep -c '8080' skills/briefing/scripts/briefing.cjs` returns 0.
- [ ] `grep -c "'scripts', 'port.sh'" skills/briefing/scripts/briefing.py` returns 0 (old path gone).
- [ ] `grep -c "scripts/port.sh" skills/briefing/scripts/briefing.py` returns 0 (no stale path under any quoting).
- [ ] `grep -c "'.claude', 'skills', 'update-zskills', 'scripts', 'port.sh'" skills/briefing/scripts/briefing.py` returns at least 2 (the two updated sites).
- [ ] Equivalent paths-not-stale checks for briefing.cjs.
- [ ] Both files have the invariant comment at the top.
- [ ] In the `/tmp/zskills-briefing-fixture-noport` test, both briefing.py and briefing.cjs run to completion and emit no `localhost:` URL.
- [ ] Their output structures are equivalent on the fixture (parity test passes).
- [ ] `diff -rq skills/briefing .claude/skills/briefing` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 2 (port.sh's tightened runtime-read + fail-loud is what this phase relies on for failure-mode testing).

## Phase 5 — Documentation surfaces

### Goal

Bring the remaining hardcoded `8080` references in active documentation into line with the new model. Keep skills' source and `.claude/skills/` mirrors in sync.

### Work Items

- [ ] 5.1 — Edit `skills/briefing/SKILL.md`. The active `:8080` references are at lines 141, 151, 158 (verified by grep — three sites in the example output block lines 137-161). All three are example URLs in the "Present the output in this format" block. Replace each instance of `localhost:8080/...` with `localhost:<port>/...` (matching the existing `<port>` placeholder convention already used at line 133 of the same file). Use the canonical replacement consistently across all three sites.

- [ ] 5.2 — Edit `skills/manual-testing/SKILL.md` line 18. Current line:
  > `# Get the correct port for this project root (8080 for main, unique per worktree)`
  
  Replace with:
  > `# Get the correct port for this project root (configured via dev_server.default_port for main; unique per worktree; consumer dev-port.sh stub may override)`

- [ ] 5.3 — Mirror both skill source edits to `.claude/skills/`:
  ```bash
  bash scripts/mirror-skill.sh briefing
  bash scripts/mirror-skill.sh manual-testing
  ```

### Design & Constraints

**What's out:**
- `plans/ZSKILLS_MONITOR_PLAN.md` and any `plans/*.md` historical artifacts — leave alone (plan-archive hygiene; standard PR #62 rule).
- `tests/test-hooks.sh` `:8080` substrings — out of scope from the plan's Overview (these test the safety hook's `fuser -k <port>` deny-pattern; the literal port number is part of the test scenario, not the system under test).
- `CLAUDE.md:18` — the `<!-- Serve locally with: npx http-server -p 8080 -->` HTML-commented-out aside in this repo's own CLAUDE.md. Verified — this is purely an HTML-author convenience aside, not read by any tool, not rendered into any consumer artifact. **Leave alone.**
- `tests/test-port.sh` literal `8080` references — these test that this repo's own `default_port: 8080` config produces port 8080 from port.sh (verified — multiple sites accept `8080` as a valid value). Keep as-is.

### Acceptance Criteria

- [ ] `grep -c '8080' skills/briefing/SKILL.md` returns 0.
- [ ] `grep -c '8080' skills/manual-testing/SKILL.md` returns 0.
- [ ] `diff -rq skills/briefing .claude/skills/briefing` empty.
- [ ] `diff -rq skills/manual-testing .claude/skills/manual-testing` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases P1.A, 2, 3, 4 (conceptually independent of all but Phase 1, but landing last avoids merge thrash with the substantive changes; WI 5.2's prose mentions the dev-port.sh stub which the user will recognize as already-shipped).

## Out of Scope

- **`skills/zskills-dashboard/scripts/zskills_monitor/server.py:107-131` regex tightening.** Verified — server.py contains its own regex `\"dev_server\"\s*:\s*\{[^}]*?\"default_port\"\s*:\s*([0-9]+)` (loose `[^}]*?` pattern with re.DOTALL). Same nested-object-traversal vulnerability as port.sh's pre-tightening regex. **Defer until ZSKILLS_MONITOR_PLAN settles** — that plan is in flight in another session with uncommitted edits to server.py. Address in a separate follow-up plan after monitor settles. This plan's scope is bounded to: port.sh, briefing scripts, CLAUDE_TEMPLATE.md, and `update-zskills`/`briefing`/`manual-testing` skill SKILL.md files only.
- **Auto-detection from framework conventions** (Vite, Django, Rails, etc.). User decision: deferred. Each consumer sets `dev_server.default_port` manually in their config; the schema default of `8080` is the universal starting point. A future plan can revisit if user demand emerges.
- **Single-sourcing the `8080` default across schema and install template.** Today the default lives in two places (`config/zskills-config.schema.json` schema default at line 93, `skills/update-zskills/SKILL.md` install template literal at line 281). This plan keeps them in sync via acceptance criteria but does not eliminate the duplication. A future refactor could derive install-template values from the schema; that's a `/update-zskills`-shape change.
- **Implementing default_port backfill into `/update-zskills`.** Phase P1.A corrects the CHANGELOG aspirational claim. Backfill is real follow-up work (mirror the `commit.co_author` backfill block at SKILL.md:226-236, but for `dev_server.default_port`). Until then, consumers with old configs hit the fail-loud message from port.sh and run `/update-zskills` (which today rewrites the schema link but not the field). This is the deliberate trade-off documented in P1.A's Design & Constraints.
- **Broadening `warn-config-drift` coverage to non-Edit/non-Write paths.** Today the hook fires only on Claude Code `Edit` and `Write` PostToolUse matchers (`.claude/settings.json:30-51`). External edits (IDE, `git pull`, `sed`, `gh secret set`, Bash tool, CI workflows) bypass it entirely. A SessionStart-hook approach that hashes the config and compares against last-render snapshot would close most of the gap; that's a separate `warn-config-drift.sh` enhancement.
- **`tests/test-hooks.sh` `:8080` deny-pattern substrings.** These test that the safety hook blocks `fuser -k <port>` regardless of port number; leaving them alone preserves the test's invariant.
- **`plans/ZSKILLS_MONITOR_PLAN.md` historical reference.** Plan-archive hygiene: don't edit `plans/` or `reports/`.
- **Tightening the existing `main_repo_path` regex from `[^}]*` to `[^{}]*`.** Theoretically vulnerable to the same nested-object issue this plan tightens for `default_port`, but lower-risk in practice (string field, no nested-object precedent). Out of scope; can be done as a sweep in a follow-up.
- **SCRIPTS_INTO_SKILLS coupling residual.** The original out-of-scope note covered "if SCRIPTS_INTO_SKILLS lands during execution"; that landing already happened (PRs #97-#100 verified by recent `git log`), so the note is reframed: the path drift it caused is now ABSORBED by this round-1 refinement (Phase 4 path fix; port.sh location update). No remaining mid-execution-drift hazard from that plan.
- **Strip-legacy-port_script code retention.** WI P1.A.2 removes the greenfield-template emit; the SKILL.md:1075-1088 stripper code stays (still needed for existing consumer configs that have the field carried over from old installs). Eventually retiring the stripper is a separate cleanup.

## Disposition Table — Round 1 Adversarial Review

| # | Source | Finding (summary) | Evidence | Disposition |
|---|--------|-------------------|----------|-------------|
| R1 | Reviewer | Phase 1 WIs 1.1-1.3 already landed; Progress Tracker stale | **Verified** — `grep -n default_port config/zskills-config.schema.json` matches at L91; `.claude/zskills-config.json:25` has the field; `skills/update-zskills/SKILL.md:281` has greenfield template entry | **Fixed**: WIs 1.1-1.3 stripped from plan body; Progress Tracker marks Phase 1 partial; Drift Log entry added for landed sub-WIs |
| R2 | Reviewer | WI 2.2 obsolete — test-all.sh is now a 17-line failing stub | **Verified** — `wc -l scripts/test-all.sh` returns 18 (with trailing blank); contents are stub callout per stub-callouts.md | **Fixed**: WI 2.2 stripped entirely from Phase 2 |
| R3 | Reviewer | Briefing scripts at `skills/briefing/scripts/`, not top-level `scripts/`; line numbers drifted | **Verified** — `find . -name briefing.py` returns `./skills/briefing/scripts/briefing.py`; `grep -n viewer_url` shows current line numbers (briefing.py:861, 1135; briefing.cjs:782, 1101) | **Fixed**: All Phase 4 paths/lines re-anchored to current state |
| R4 | Reviewer | WI 2.1 partially landed with deviations: loose `[^}]*`, retains `DEFAULT_PORT=8080`, uses `git rev-parse --show-toplevel` | **Verified** — `skills/update-zskills/scripts/port.sh:18` uses git rev-parse; line 20 has `DEFAULT_PORT=8080` fallback comment; line 38 has loose `[^}]*` | **Fixed (3-way decision)**: (a) loose regex pushed forward as new WI 2.1 to tighten; (b) literal `DEFAULT_PORT=8080` fallback pushed forward as WI 2.3 to remove + fail-loud; (c) `git rev-parse` derivation RATIFIED (the script-bundle-relocation made the original `cd $SCRIPT_DIR/..` impossible; ratified with `${PROJECT_ROOT:-...}` env-override added in WI 2.2) |
| R5 | Reviewer | Fail-loud philosophy vs dev-port.sh stub silent fall-through; precedence ambiguous | **Verified** — port.sh:51-77 stub callout block; lines 67-69 emit warning on non-numeric stdout; lines 70-71 silent fall-through on empty | **Fixed**: WI 2.3 scopes fail-loud to main-repo branch (after stub callout already returned); WI 2.4 documents the precedence chain in port.sh header comment. Stub silent fall-through is preserved |
| R6 | Reviewer | WI 2.1 PROJECT_ROOT env override pattern doesn't apply to current script (cd $SCRIPT_DIR/.. obsolete) | **Verified** — port.sh now uses `git rev-parse --show-toplevel` not `cd $SCRIPT_DIR/..` (header comment at lines 12-17 documents why) | **Fixed**: WI 2.2 specifies `${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null \|\| pwd)}` matching the current shape |
| R7 | Reviewer | WI 1.4 (default_port backfill) never landed; CHANGELOG claim aspirational | **Verified** — `grep -n default_port skills/update-zskills/SKILL.md` shows no occurrence in backfill block (lines 226-236, only co_author backfill); CHANGELOG.md:91 claims "/update-zskills writes default_port on greenfield install and backfills it into existing configs" | **Fixed (Decision: correct CHANGELOG, defer backfill)**: New Phase P1.A WI P1.A.1 corrects CHANGELOG to reflect actual ship state; backfill added to Out of Scope as future work |
| R8 | Reviewer | `{{MAIN_REPO_PATH}}` active leak — used in template but not mapped | **Verified** — `CLAUDE_TEMPLATE.md:22` contains `{{MAIN_REPO_PATH}}`; `skills/update-zskills/SKILL.md:319-324` mapping table does NOT include the row (only `{{DEV_SERVER_CMD}}` and `{{AUTH_BYPASS}}` rows present) | **Fixed (severity: active shipping bug, not "while you're there")**: Phase 3 WI 3.2 explicitly adds the row; ACs verify end-to-end substitution in fixture render |
| R9 | Reviewer | Mirror snippets `rm -rf .claude/skills/X && cp -r ...` are hook-blocked per PR #88 | **Verified** — `hooks/block-unsafe-generic.sh` blocks variable-bearing recursive rm (the hook fired on a refinement-time grep against the hook itself); `scripts/mirror-skill.sh` exists at lines 1-40 verified, designed as the hook-compatible replacement | **Fixed**: All mirror snippets in WIs 2.6, 3.5, 4.5, 5.3 use `bash scripts/mirror-skill.sh <name>` |
| R10 | Reviewer | CLAUDE_TEMPLATE.md:22 prose was rewritten end-to-end (no more `**8080**` bold; mentions stub callout) | **Verified** — current line 22 reads "The port is determined automatically (8080 for the main repo `{{MAIN_REPO_PATH}}`...)"; no bold; mentions dev-port.sh stub | **Fixed**: Phase 3 WI 3.1 re-derives the prose against current shape; substitutes `{{DEFAULT_PORT}}` with stub-override caveat (per /refine-plan instruction item 9 — option (a)) |
| R11 | Reviewer | Briefing path lookup `os.path.join(main_path, 'scripts', 'port.sh')` is silent-failing today | **Verified** — `find . -name port.sh` returns only `skills/update-zskills/scripts/port.sh`; briefing.py:803 and :1114 use the stale `main_path/scripts/port.sh` path; condition `if os.path.exists(port_sh)` swallows the miss; falls through to `or '8080'` | **Fixed**: NEW WI 4.0 added — fix path lookup BEFORE removing fallback (load-bearing ordering documented in Phase 4 D&C); per /refine-plan instruction item 8 |
| R12 | Reviewer | CHANGELOG aspirational decision (R7 same finding under different framing) | Same as R7 | **Fixed (same as R7)**: corrected, not implemented |
| R13 | Reviewer | Mirror command hook conflict (R9 same finding) | Same as R9 | **Fixed (same as R9)** |
| R14 | Reviewer | Briefing path bug + CLAUDE_TEMPLATE prose rewrite jointly require Phase 4 path-fix-before-removal ordering | Composite — same evidence as R10 + R11 | **Fixed**: WI 4.0 ordering documented in Phase 4 D&C |
| R15 | Reviewer | Greenfield template still writes `"port_script": ""` (then strips it) — incoherent | **Verified** — SKILL.md:282 writes the field; SKILL.md:1075-1088 strips it; schema does not contain `port_script` (`grep port_script config/zskills-config.schema.json` empty) | **Fixed**: WI P1.A.2 removes the writer; keeps the stripper (still needed for old consumer configs) |
| R16 | Reviewer | Phase 5 line numbers (briefing/SKILL.md:141,151,158; manual-testing/SKILL.md:18) | **Verified** — current grep matches those exact lines | **Fixed (no change)**: line numbers confirmed; WIs reference them correctly |
| R17 | Reviewer | tests/test-port.sh has multiple `8080` literal references that may need updating | **Verified** — `grep -n 8080 tests/test-port.sh` matches lines 47-49, 95, 98, 121, 136, 154 | **Fixed (judgment: keep)**: These tests use `8080` as a "tolerate either worktree-hash range OR 8080" disjunction. With this repo's own `.claude/zskills-config.json` containing `default_port: 8080`, the literal `8080` remains a valid expected value. No edit needed |
| R18 | Reviewer | DRIFT_ARCH_FIX cross-reference at SKILL.md:326 may be stale | Judgment | **Justified**: The plan referenced is a real artifact in `plans/`; cross-reference is informational. WI 3.4 rewords the prose without removing the cross-ref |
| R19 | Reviewer | --rerender flow at SKILL.md:1208+ may need updating for new placeholders | **Verified** — SKILL.md:1240 says "--rerender does NOT do: re-run the audit, backfill config fields, apply a preset…"; substitution flows through Step B which IS run by --rerender per line 1218 | **Justified — confirming**: --rerender already invokes Step B substitution (no special carve-out for new placeholders); WI 3.6 tests verify --rerender path |
| R20 | Reviewer | WI 4.4 normalization "etc." vague language | Judgment + tests/test-briefing-parity.sh existing structure | **Fixed**: WI 4.4 specifies enumerate-or-refactor with concrete grep, no "etc." |
| R21 | Reviewer | WI 3.5 `cp CLAUDE_TEMPLATE.md .claude/CLAUDE_TEMPLATE.md` may not be needed | Judgment | **Fixed**: WI 3.5 wraps the cp in an if-exists guard; explicit comment notes mirror-skill.sh doesn't cover root-level templates |
| R22 | Reviewer | Worktree-hash test in test-port.sh at line 95 says `[ "$out" -ge 9000 && "$out" -le 60000 ] || [ "$out" == "8080" ]` — may interact with fail-loud | **Verified** — port.sh's RANGE_START=9000, RANGE_SIZE=51000 (lines 21-22); worktree branch unaffected by fail-loud (which only fires in main-repo branch) | **Justified — no conflict**: fail-loud is main-repo-branch-scoped (WI 2.3 design); worktree tests stay valid |
| R23 | Reviewer | Phase ordering: P1.A vs Phase 2 dependency | Judgment | **Fixed**: P1.A.1 (CHANGELOG) and P1.A.2 (greenfield template port_script removal) declared parallel-with-Phase-2; explicit dependency note added |
| R24 | Reviewer | Hook-policy applies to refinement-time tooling — verified during this refine | **Verified** — the hook fired during my grep against `hooks/block-unsafe-generic.sh` | **Fixed**: confirms WI 9 (mirror snippets) is required, not optional |
| DA1 | DA | server.py:107-131 also reads default_port via its own regex | **Verified** — `sed -n '105,135p' skills/zskills-dashboard/scripts/zskills_monitor/server.py` shows `_CFG_DEV_PORT_RE = re.compile(r'"dev_server"\s*:\s*\{[^}]*?"default_port"\s*:\s*([0-9]+)', re.DOTALL)` at server.py:107-110 | **Justified — out-of-scope for this plan**: documented in Out of Scope as monitor-coupled future work; ZSKILLS_MONITOR_PLAN is in flight in another session and has uncommitted edits to server.py per /refine-plan instruction critical-scope-guard |
| DA2 | DA | Briefing path drift — `os.path.join(main_path, 'scripts', 'port.sh')` is stale | **Verified** — same as R11 | **Fixed (same as R11)**: NEW WI 4.0 fixes path before fallback removal |
| DA3 | DA | Mirror snippets must use `mirror-skill.sh` (hook conflict) | **Verified** — same as R9 | **Fixed (same as R9)** |
| DA4 | DA | Phase 1 → Phase 2 dependency confirmed sound (WIs 1.1-1.3 landed unblocks Phase 2) | Judgment + Verified-landed status of 1.1-1.3 | **Justified — confirming**: dependency graph is correct |
| DA5 | DA | Schema `default_port` field doesn't run validators today (informational only) | Verified — zskills doesn't run a schema validator at install (per Phase 1 D&C in original plan) | **Justified — confirming, no fix needed**: the documented constraint stands |
| DA6 | DA | Greenfield template `port_script: ""` remnant — schema field is gone | **Verified** — same as R15 | **Fixed (same as R15)**: WI P1.A.2 removes |
| DA7 | DA | `{{MAIN_REPO_PATH}}` is active shipping bug, not "while you're there" hygiene | **Verified** — same as R8; rendering produces literal `{{MAIN_REPO_PATH}}` substring in consumer's managed.md | **Fixed (severity reframed)**: Phase 3 WI 3.2 explicitly notes "active shipping bug" and the AC verifies end-to-end fixture-substitution per /refine-plan instruction item 6 |
| DA8 | DA | CLAUDE_TEMPLATE.md:22 prose rewrite — re-derive replacement strategy from current shape | **Verified** — current line 22 contains literal `8080` AND `{{MAIN_REPO_PATH}}` AND mentions dev-port.sh stub | **Fixed**: Phase 3 WI 3.1 substitutes `{{DEFAULT_PORT}}` with stub-override caveat (option (a) per /refine-plan instruction item 9); rationale: rendering literal `**8080**` would actively LIE whenever the stub returns a different value |
| DA9 | DA | Fail-loud philosophy vs dev-port.sh stub silent fall-through | **Verified** — same as R5 | **Fixed (same as R5)**: WI 2.4 documents precedence chain explicitly |
| DA10 | DA | SCRIPTS_INTO_SKILLS landed (PRs #97-#100); mid-execution drift no longer a hazard | **Verified** — `git log` shows PRs #97-#100 landed | **Fixed**: Out of Scope note reframed — the drift it caused is now ABSORBED by this refinement (no remaining mid-execution hazard from that plan) |
| DA11 | DA | Briefing parity test already exists; doesn't yet cover port-failure | **Verified** — `wc -l tests/test-briefing-parity.sh` returns 152; structural parity at JSON-keys + line-count level (lines 80-143); no port-failure cases | **Fixed**: WI 4.4 extends the existing test; no new file needed |
| DA12 | DA | tests/test-port.sh worktree-hash branch (lines 95, 121, 136, 154) tolerates 8080 OR worktree-range — interacts with fail-loud? | **Verified — no conflict**: fail-loud is main-repo-branch-scoped (WI 2.3 design); worktree branch unaffected | **Justified — no fix**: same as R22 |
| DA13 | DA | Phase 5 WI 5.2 prose change: "(8080 for main, unique per worktree)" → new wording must mention dev-port.sh stub | Judgment | **Fixed**: WI 5.2 wording explicitly mentions stub override |
| DA14 | DA | --rerender flow: does substitution path receive the new placeholders without code change? | **Verified** — same as R19 | **Justified — confirming, no code edit needed in --rerender flow** |
| DA15 | DA | Hook policy effectively requires mirror-skill.sh; refinement caught the hook firing live | **Verified** — same as R24 | **Fixed (same as R24)**: confirms WIs 2.6, 3.5, 4.5, 5.3 |

## Drift Log

This refine (2026-04-29, /refine-plan round 1) absorbed inline-landed work from PRs #88, #94-#100, #105-#106, #107-#115. Original plan was authored 2026-04-25.

### Inline-landed work via SCRIPTS_INTO_SKILLS Phase 3a (PR #97, 2026-04-28)

| WI | Original | Actual | Delta |
|----|----------|--------|-------|
| 1.1 | Add `default_port` to `config/zskills-config.schema.json` | Landed at L91-95 | Inline-landed by PR #97's "DEFAULT_PORT_CONFIG Phase 1 inline" reconciliation |
| 1.2 | Add `default_port` to this-repo `.claude/zskills-config.json` | Landed at L25 | Inline-landed by PR #97 |
| 1.3 | Add `default_port` to greenfield install template at `skills/update-zskills/SKILL.md` | Landed at L281 | Inline-landed by PR #97; residual `port_script: ""` writer at L282 covered by WI P1.A.2 |
| 1.4 | Implement `default_port` backfill into existing configs | NOT landed; CHANGELOG aspirational | Refine decision: correct CHANGELOG (P1.A.1); backfill deferred to future-work |
| 2.1 (partial) | port.sh runtime-read with tight regex, no literal fallback, PROJECT_ROOT env override | Partially landed at port.sh:38-40 with deviations (loose `[^}]*` regex, retained `DEFAULT_PORT=8080` fallback at L20, uses `git rev-parse --show-toplevel` for PROJECT_ROOT) | Tightening pushed forward into refined Phase 2 |

### File relocations absorbed (PR #97 Phase 3a, 2026-04-28)

- `scripts/port.sh` → `skills/update-zskills/scripts/port.sh`
- `scripts/briefing.py` → `skills/briefing/scripts/briefing.py`
- `scripts/briefing.cjs` → `skills/briefing/scripts/briefing.cjs`
- `scripts/test-all.sh` retained at top-level (Tier-2 consumer-customizable; converted to failing stub by PRs #105/#106)
- All Phase 2/4 paths re-anchored to current locations.

### Bug surfaced during refine

- `briefing.py:803,1114` and `briefing.cjs:708,1082` look for port.sh at `os.path.join(main_path, 'scripts', 'port.sh')` — that path no longer exists (port.sh moved to `skills/update-zskills/scripts/port.sh`). Briefing's port-discovery silently fails today and falls through to the literal `'8080'`. New WI 4.0 added to fix the path lookup BEFORE removing the fallback.

### Prose rewrites absorbed (PRs #99, #105/#106)

- `CLAUDE_TEMPLATE.md:13 → :22`: rewritten end-to-end. PR #99 removed `{{PORT_SCRIPT}}` placeholder. PRs #105/#106 added dev-port.sh stub callout guidance. Phase 3 strategy re-derived against current shape.

### Active shipping bug surfaced

- `{{MAIN_REPO_PATH}}` is referenced in `CLAUDE_TEMPLATE.md:22` but missing from `skills/update-zskills/SKILL.md:319-324`'s placeholder mapping table. Consumer renders contain a literal `{{MAIN_REPO_PATH}}` substring. Phase 3 WI 3.2 closes the gap.

### Hook policy realization (PR #88)

- PR #88 added `scripts/mirror-skill.sh`. Inline `rm -rf .claude/skills/X && cp -r ...` snippets are now hook-blocked by `hooks/block-unsafe-generic.sh` (verified during refinement: the hook fired on a refinement-time grep). All mirror snippets in refined plan use `bash scripts/mirror-skill.sh <name>`.

### Out-of-scope deferral (per parallel-safety bar)

- `skills/zskills-dashboard/scripts/zskills_monitor/server.py:107-131` reads `dev_server.default_port` via its own loose-regex pattern (`[^}]*?`). Same nested-object-traversal vulnerability as port.sh's pre-tightening regex. Deferred to a separate follow-up plan after ZSKILLS_MONITOR_PLAN settles (in flight in another session as of refine date). See Out of Scope.

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

## Plan Review

**Refinement process:** /refine-plan with 1 round of adversarial review (orchestrator-judgment convergence per PR #82; user-budgeted rounds=2 short-circuited at round 1 because substantive issues = 0 after disposition).
**Convergence:** Converged at round 1. The lone "Justified-not-fixed" was DA1's monitor-coupling finding, properly documented in Out of Scope per the user's parallel-safety bar (ZSKILLS_MONITOR_PLAN in flight).
**Remaining concerns:** None blocking. server.py:107-131 regex tightening deferred to a separate follow-up plan after monitor settles.

### /refine-plan Round History (this refine, 2026-04-29)

| Round | Reviewer Findings | Devil's Advocate Findings | Substantive | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 24 (5 blocker, 7 major, 9 minor, 3 spec) | 15 (2 blocker, 7 major, 5 minor, 1 spec) | 0 | 30 fixed; 9 justified-not-fixed (5 confirming, 1 out-of-scope/monitor-coupled, 3 same-as-prior-fix) |

The disposition table for this refine's round 1 is at the previous section ("Disposition Table — Round 1 Adversarial Review", written by /refine-plan Phase 3 refiner). The earlier Plan Quality / Disposition Tables (rounds 1-3) describe the original /draft-plan + /refine-plan history from 2026-04-25.
