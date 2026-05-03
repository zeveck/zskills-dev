---
title: Verifier Agent Fix
created: 2026-05-02
status: active
---

# Plan: Verifier Agent Fix

> **Landing mode: PR — single PR, ordered commits** — All 6 phases land as ordered commits in a single PR; **no per-phase merge to main** while the plan is in progress. Mid-plan windows where dispatchers reference `subagent_type:` parameters before the agent files exist (or vice versa) never become visible on `main`. This plan creates one new agent definition under `.claude/agents/` (`verifier.md`), two new hook scripts under `hooks/` (`inject-bash-timeout.sh` Layer 0, `verify-response-validate.sh` Layer 3) mirrored to `.claude/hooks/`, edits 5 source skills, extends `/update-zskills` Step C install + audit flow, and adds 3 canaries + test-suite registration. PR review is appropriate.

## Overview

Subagents dispatched by `/run-plan`, `/commit`, `/fix-issues`, `/do`, and `/verify-changes` reflexively reach for `Bash(run_in_background: true)` + `Monitor`/`BashOutput` polling when a foreground test invocation hits the default 120s Bash-tool timeout — wake events for backgrounded processes do not reliably deliver to one-shot subagent dispatches, so the wait never returns and the dispatch hangs at "Tests are running. Let me wait for the monitor." PR #148 (`2107db3`, 2026-05-01) added verbatim "DO NOT use `run_in_background: true`" prose warnings to four SKILL.md files; PR #175 (skill-versioning, 2026-05-02) demonstrated those warnings fail mechanically — every Phase 1-6 verifier dispatch hit the Monitor pattern. The orchestrator did inline verification across 5 of 7 phases, violating zskills's saved principle that "verifier-cannot-run is FAIL, never a routing decision" (`feedback_verifier_test_ungated.md`). Two GitHub issues filed against `zeveck/zskills-dev` 2026-05-02 capture the gap: **#176** (Monitor anti-pattern recurrence despite the verbatim warning) and **#180** (verifier-skipped silent pass — orchestrator logs a one-line note and proceeds instead of invoking the Failure Protocol).

This plan replaces the prose-only guardrail with a **structural** fix at two layers (D'' refined architecture, see Drift Log 2026-05-03). **Layer 0** — a frontmatter `PreToolUse` hook on Bash (`hooks/inject-bash-timeout.sh`) that uses the `updatedInput` envelope field to ensure every Bash call from the verifier subagent gets at least `timeout: 600000` (10 min). This addresses the root cause directly: once Bash never times out at 120s, the bg+Monitor recovery reflex never triggers. The verifier agent definition at `.claude/agents/verifier.md` keeps the full tools allowlist (`Read, Grep, Glob, Bash, Edit, Write`) because the structural restrictions on Monitor/BashOutput are no longer needed — Layer 0 prevents the trigger. **Layer 3** — a script-based universal failure-protocol primitive (`hooks/verify-response-validate.sh`) that any verifier-dispatching skill pipes the verifier's response through. Reads stdin, checks for stalled-string patterns (whitelist of 7 phrases anchored to last 10 lines) plus a 200-byte minimum-length signal. Exit 0 = PASS; exit 1 = FAIL with reason on stderr. Applied at all 5 dispatch sites (`/run-plan` Phase 3, `/commit` Phase 5 step 3, `/fix-issues` per-issue, `/do` Phase 3 code path, `/verify-changes` self-dispatch) via the same small invocation block. Five dispatch sites gain explicit `subagent_type: "verifier"` parameters at their `Agent`-tool dispatches. `/update-zskills` Step C is **extended** (not given a sibling step) to also copy `.claude/agents/<name>.md` files plus both new hook scripts (`inject-bash-timeout.sh`, `verify-response-validate.sh`) alongside the existing hook copy, so consumer repos receive the structural fix without manual setup.

**Success criterion:** A fresh `/run-plan` invocation that dispatches a verification subagent for a long-running test suite (one whose runtime exceeds the default 120s Bash-tool timeout) **never hangs at "Tests are running. Let me wait for the monitor."** because the Layer 0 hook auto-extends Bash timeouts to 10 minutes. If the verifier fails for any other reason — including returning empty/no-results, returning a stalled-string trailer, or exceeding the 45-min agent timeout — the Layer 3 script signals FAIL and the orchestrator STOPs and invokes the Failure Protocol; it does NOT log a one-line note and proceed. Closes #176 and #180. PR #148's prose warnings stay in place as belt-and-suspenders (the structural fix is primary; prose is documentation). The `.claude/agents/verifier.md` file plus both hook scripts ship through `/update-zskills` so a fresh consumer install of zskills picks up the structural fix automatically.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Verifier agent + Layer 0 timeout-injection hook + Layer 3 failure-protocol script | ✅ | `89d1b57` (initial) + D'' rework commit | Phase 1 originally shipped the L1+L2 architecture (allowlist exclusion + bg-rejection hook + commit-reviewer.md). User pushback + research surfaced the D'' refined architecture: drop L1/L2 (working AROUND the harness bug, not addressing root cause), add Layer 0 timeout-injection hook + Layer 3 universal script-based failure-protocol primitive. Phase 1 reworked in the same PR; commit-reviewer.md + the two old validation hooks removed; verifier.md kept with full tools allowlist. Canary `canary-verifier-agent-discovery-part1.sh` retained (verifies subagent auto-discovery, not allowlist semantics). See Drift Log 2026-05-03. |
| 2 — Migrate `/run-plan` Phase 3 verifier dispatch + Layer 3 invocation | ✅ | `636eccb` | D'' Layer 3 invocation: subagent_type:"verifier" + verify-response-validate.sh pipe + STOP on exit 1 in /run-plan/SKILL.md Phase 3; metadata.version 2026.05.03+82aa34; conformance tripwires +4; tests 2049/2049 PASS. |
| 3 — Migrate `/commit`, `/fix-issues`, `/do`, `/verify-changes` (4 skills, same pattern) | ✅ | `d6690d0` (3-A /commit) + `285bc1d` (3-B /fix-issues) + `cf2fc56` (3-C /do) + `5919ea9` (3-D /verify-changes) | All 12 ACs PASS. 4 ordered commits per spec's commit-boundary rule. Each skill: subagent_type:"verifier" + Layer 3 invocation + Dispatch-shape callout. /commit retains read-only preamble verbatim; /do has 2 dispatch sites wired (code-changes + content-only); /verify-changes documents freshness modes (multi-agent / single-context fresh-subagent / inline self-review). metadata.version bumped on all 4 (commit→`+e8e557`, fix-issues→`+8c4e2f`, do→`+27f0e7`, verify-changes→`+d5c06b`). Tests 2049/2049 PASS (parity with baseline). |
| 4 — Canaries: tools-allowlist, timeout-injection, failure-protocol script | ✅ | `b2a968e` | All 5 ACs PASS. Canary 2 `tests/canary-verifier-timeout-injection.sh` (7 assertions): source/mirror parity for inject-bash-timeout.sh + verifier.md frontmatter PreToolUse Bash matcher + 3 hook-script invocation cases (probe / real injection / no-op on already-sufficient). Canary 3 `tests/canary-verify-response-validate.sh` (11 sub-cases A-G): 5 baseline + 3 positive threshold-calibration (F-a/b/c realistic ≥200-byte attestations) + 3 negative (G-a/b/c stubs). Both registered in tests/run-all.sh. Tests 2067/2067 PASS (+18 vs baseline). Phase 3.5 auto-corrected 1 PLAN-TEXT-DRIFT (G-a byte-count: 8→7, 13% drift, 10-20% band). |
| 5 — `/update-zskills` install path for verifier.md + 2 new hooks | ✅ | `a4b0890` | All 10 ACs PASS (incl. AC-5.7 manual install in scratch dir at `/tmp/zskills-scratch-consumer`). Step C extended in place: heading "Fill hook + agent gaps", hook list +2 (inject-bash-timeout.sh + verify-response-validate.sh), agent-copy bash block (cmp -s gated, idempotent), auto-discovery WARN line, install-summary "Installed agents/hooks" + drift-check lines. metadata.version → `2026.05.03+a9bbe0`. tests/test-update-zskills-agent-install.sh (new): 4 sandbox sub-cases (fresh / byte-equiv / idempotent / update-on-change). tests/test-update-zskills-version-surface.sh AC #8: jq invariant refined from substring grep to invocation-shape regex (documentation disclaimers exempt) — bundled into Phase 5 commit because spec's "no jq" disclaimer at SKILL.md:886 caused the cross-plan collision the spec author didn't anticipate. Tests 2071/2071 PASS (+4 vs baseline 2067). |
| 6 — CHANGELOG, file Anthropic issue, plan completion | ⬚ |        |       |

---

## Phase 1 — Verifier agent + Layer 0 timeout-injection hook + Layer 3 failure-protocol script

### Status

**Done.** Originally landed in commit `89d1b57` with the L1+L2 architecture (tools-allowlist excluding Monitor/BashOutput on `verifier.md`; PreToolUse `validate-bash-no-background.sh` rejecting `run_in_background: true`; separate `commit-reviewer.md` with additional `validate-bash-readonly.sh`; manual canary). Reworked in a follow-on commit on the same PR branch to the D'' refined architecture per user pushback (Drift Log 2026-05-03). The reworked Phase 1 is what ships in this PR; the original L1+L2 design is preserved in commit history for reviewer context.

### Goal

Author the verifier agent definition (`.claude/agents/verifier.md`) and the two hook scripts the architecture relies on:

- **Layer 0** — `hooks/inject-bash-timeout.sh`: a frontmatter PreToolUse hook on Bash that ensures every Bash call from the verifier gets at least `timeout: 600000` (10 min). The default 120s tool timeout was the root cause of the bg+Monitor recovery reflex; Layer 0 prevents the trigger.
- **Layer 3** — `hooks/verify-response-validate.sh`: a universal script that any verifier-dispatching skill pipes the verifier's response through. Catches stalled-string trailers and sub-200-byte responses uniformly across all 5 sites. Future-extensible (add new pattern arrays for Anthropic backend errors etc. without touching call sites).

Encode the "verifier-cannot-run is FAIL" rule in CLAUDE.md. No source skill edits in this phase — this phase produces the artifacts the migration phases (2, 3, 5) reference.

### Work Items (as shipped)

- [x] 1.1 — **Auto-discovery canary (retained from original Phase 1).** `tests/canary-verifier-agent-discovery-part1.sh` writes a fixture agent file at `.claude/agents/canary-readonly.md` and prints the verbatim restart instruction; `tests/canary-verifier-agent-discovery-part2.sh` (manual, post-restart) dispatches `Agent(subagent_type: "canary-readonly", …)` and asserts the dispatched subagent does not produce the literal token a Bash call would have emitted. The canary verifies that `.claude/agents/*.md` is auto-discovered at session start (the deployment path consumers exercise) — independent of the L1/L2-vs-D'' choice. **Retained because subagent auto-discovery is still load-bearing for the D'' architecture.** Manual gate; CI registers part1 only. Original Phase 1 canary PASSED 2026-05-03 against Claude Code 2.1.126.

- [x] 1.2 — **Author `.claude/agents/verifier.md`.** Frontmatter:

  ```yaml
  ---
  name: verifier
  description: Read diffs, run tests, validate plan acceptance criteria against worktree state, commit verified changes. Dispatched explicitly by /run-plan, /fix-issues, /do, /verify-changes — never auto-invoked.
  tools: Read, Grep, Glob, Bash, Edit, Write
  model: inherit
  hooks:
    PreToolUse:
      - matcher: "Bash"
        hooks:
          - type: command
            command: "bash $CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh"
  ---
  ```

  Body: explains that Bash timeouts are auto-extended to 10 min by the frontmatter hook (so the agent does not need to manage timeouts manually); restates the test-output-to-file convention; restates the "subagents cannot dispatch sub-subagents" Anthropic-design rule. Body deliberately does NOT contain the prose ban on `run_in_background: true` — Layer 0 makes that ban unnecessary, and the prose was redundant scaffolding from the original L1+L2 design.

  **Allowlist justification:** `Read, Grep, Glob` for diff/plan/source reading; `Bash` for tests + git + helper scripts; `Edit, Write` for verifiable fixes (version bumps, tracking marker writes, report writes). NO exclusions on `Monitor`/`BashOutput` — Layer 0 prevents the timeout that triggers their use; structurally restricting them was working AROUND the harness bug rather than addressing root cause. `Agent` is excluded structurally (subagents categorically cannot dispatch sub-subagents per Anthropic design). `WebFetch`, `WebSearch`, `Skill` are excluded as out-of-scope for verification.

  **`model: inherit`** — matches CLAUDE.md "default OMIT model — inherit parent" rule. MUST NOT be `haiku`.

- [x] 1.3 — **Author `hooks/inject-bash-timeout.sh` (Layer 0).** PreToolUse hook on Bash. Reads the JSON envelope from stdin; if the existing `timeout` field is already ≥ 600000, returns `permissionDecision=allow` with no `updatedInput`; otherwise returns `permissionDecision=allow` with `updatedInput` preserving every original tool_input field (including `command`, `run_in_background`, `description`, etc.) and setting `timeout: 600000`. **Implementation choice:** the `command` field can contain arbitrary quotes, backslashes, and newlines that are awkward to round-trip through pure bash regex — the script uses `python3` for the JSON parse + reserialize step. Per zskills convention: no `jq`; Python is acceptable in hook scripts when bash JSON construction would be brittle. The script auto-detects two stdin shapes: full PreToolUse envelope (`{"tool_name":"Bash","tool_input":{…}}`) or bare tool_input (`{"command":"…","timeout":…}`). Mirrors at install time to `.claude/hooks/inject-bash-timeout.sh`.

- [x] 1.4 — **Author `hooks/verify-response-validate.sh` (Layer 3).** Universal script (NOT a hook — designed for caller-driven invocation). Reads the verifier's response on stdin; exit 0 = PASS, exit 1 = FAIL with reason on stderr. Pure bash (no JSON construction needed). Two patterns:
  - **Stalled-string whitelist** (case-insensitive substring match, **anchored to the LAST 10 LINES** of the response): 7 phrases — `let me wait for the monitor`, `tests are running. let me wait`, `monitor will signal`, `monitor to signal`, `still searching. let me wait`, `waiting on bashoutput`, `polling bashoutput`. The last-10-lines anchor prevents contamination from the verifier quoting documentation that mentions the trigger phrase.
  - **Min-byte threshold** (200 bytes). A real verification report is at minimum a sentence or two of explanation, well over 200 bytes. Shorter responses are either empty (the agent ended its turn before producing meaningful output) or stubs that do not constitute attestation.

  Pattern arrays designed for easy extension — append `PATTERNS_BACKEND_ERROR` etc. without touching call sites. Mirrors at install time to `.claude/hooks/verify-response-validate.sh`.

- [x] 1.5 — **Author `tests/test-inject-bash-timeout.sh`** (registered in `tests/run-all.sh`). 7 cases: already-sufficient timeout → no `updatedInput`; already-larger timeout (900000) → no `updatedInput` (no downgrade); insufficient timeout (60000) → `updatedInput` with timeout=600000 + command preserved; missing timeout field → same; `run_in_background:true` + missing timeout → both preserved AND timeout set; bare tool_input shape (no envelope) → still injects; command with embedded escaped quotes → round-trips correctly.

- [x] 1.6 — **Author `tests/test-verify-response-validate.sh`** (registered in `tests/run-all.sh`). 5 cases: normal long response with no stalled patterns → exit 0; stalled-string in last 10 lines → exit 1, stderr names matched pattern; sub-200-byte response → exit 1, stderr names threshold; empty response → exit 1; stalled-string in EARLIER lines but recovered in tail → exit 0 (the last-10-lines anchor lets the agent recover).

- [x] 1.7 — **Append CLAUDE.md "Verifier-cannot-run rule" section** (single paragraph; verbatim text from original Phase 1.7, retained — wording does not depend on architecture choice).

### Design & Constraints (D'' as shipped)

- **Layer 0 addresses root cause, not symptom.** The original L1+L2 (allowlist exclusion + bg-rejection hook) prevented the bg+Monitor reflex by structurally removing the channel. D'' prevents the *trigger* (Bash timeout at 120s) — the reflex never engages because the verifier's Bash calls do not time out. This better matches the "skill-framework repo — surface bugs, don't patch" principle in CLAUDE.md: the underlying harness bug (subagent wake events not delivering for backgrounded processes) is still surfaced via the Layer 3 script when the response trailer matches; we just stop *triggering* it from our own dispatches.
- **Layer 3 is a script, not a hook.** Hooks fire on tool-call boundaries; the verifier-response check fires once per dispatch return, in the orchestrator. A script invoked from each dispatch site is the right primitive.
- **Layer 3 is universal.** All 5 dispatch sites use the same script; the failure-protocol detection is the same wherever it fires. Phases 2 and 3 wire the invocation in.
- **`commit-reviewer.md` is dropped.** The original design used it for read-only enforcement at /commit Phase 5 step 3 (with `validate-bash-readonly.sh`). The read-only constraint there was solving an L2-style problem (preventing the reviewer from running `git stash -u && pop` and silently unstaging the caller's work). With L2 dropped, the reviewer-vs-verifier distinction has no structural carrier — and read-only-by-prose is exactly the discipline PR #148 proved insufficient. Resolution: `/commit` Phase 5 step 3 dispatches `subagent_type: "verifier"` with a prose preamble in the dispatch prompt that says "review only — do not stage, unstage, stash, or commit." If a future incident shows prose insufficient there, surface the bug; do not patch by re-introducing a separate agent definition.
- **`model: inherit` only.** Per CLAUDE.md.
- **Bash + Python (no jq).** `inject-bash-timeout.sh` uses Python for JSON round-trip; `verify-response-validate.sh` is pure bash (no JSON construction needed).
- **No source skill `metadata.version` bumps in this phase.** Phase 1 lands `.claude/agents/`, `hooks/`, `tests/`, `CLAUDE.md` only. Skill bumps land in Phases 2, 3, and 5.
- **Mirror the agent file into `.claude/agents/`** and both hook scripts into `.claude/hooks/` at the same commit (zskills uses source `skills/` + mirrored `.claude/skills/` for agent-tool consumption; same convention applies to `.claude/agents/` and `.claude/hooks/`).
- **Commit boundary (Phase 1, as shipped after rework):** the rework is one commit that pivots the original Phase 1 commit (`89d1b57`) to D''. Files in the rework commit:
  - **Modified:** `.claude/agents/verifier.md` (hook reference + body text), `tests/run-all.sh` (test registrations swapped), `plans/VERIFIER_AGENT_FIX.md` (this plan rewrite + Drift Log).
  - **Removed:** `.claude/agents/commit-reviewer.md`; `hooks/validate-bash-no-background.sh` + `.claude/hooks/` mirror; `hooks/validate-bash-readonly.sh` + `.claude/hooks/` mirror; `tests/test-validate-bash-no-background.sh`; `tests/test-validate-bash-readonly.sh`.
  - **Added:** `hooks/inject-bash-timeout.sh` + `.claude/hooks/` mirror; `hooks/verify-response-validate.sh` + `.claude/hooks/` mirror; `tests/test-inject-bash-timeout.sh`; `tests/test-verify-response-validate.sh`.
  - **Unchanged from original Phase 1:** `tests/canary-verifier-agent-discovery-part1.sh` + `part2.sh`; `tests/fixtures/canary-agents/canary-readonly.md`; `CLAUDE.md` "Verifier-cannot-run rule" section.

### Acceptance Criteria (D'' as shipped)

- [x] AC-1.1 — `bash tests/canary-verifier-agent-discovery-part1.sh` exits 0 and prints the restart instruction. Manual part2 (post-restart) PASSED 2026-05-03 against Claude Code 2.1.126.
- [x] AC-1.2 — `[ -f .claude/agents/verifier.md ]` exists; `.claude/agents/commit-reviewer.md` does NOT exist.
- [x] AC-1.3 — `awk '/^---$/{f=!f;next} f && /^tools:/' .claude/agents/verifier.md` returns `tools: Read, Grep, Glob, Bash, Edit, Write`. (`Monitor`/`BashOutput` are NOT excluded structurally; Layer 0 prevents their misuse.)
- [x] AC-1.4 — `awk '/^---$/{f=!f;next} f && /^model:/' .claude/agents/verifier.md` returns `model: inherit`. `! grep -q 'haiku' .claude/agents/verifier.md`.
- [x] AC-1.5 — `awk '/^---$/{f=!f;next} f' .claude/agents/verifier.md | grep -F 'inject-bash-timeout.sh'` returns 1+ line; `awk '/^---$/{f=!f;next} f' .claude/agents/verifier.md | grep -F 'validate-bash-no-background'` returns no output.
- [x] AC-1.6 — `[ -x hooks/inject-bash-timeout.sh ] && [ -x .claude/hooks/inject-bash-timeout.sh ]` AND `bash tests/test-inject-bash-timeout.sh` exits 0 with all 7 cases PASS.
- [x] AC-1.7 — `[ -x hooks/verify-response-validate.sh ] && [ -x .claude/hooks/verify-response-validate.sh ]` AND `bash tests/test-verify-response-validate.sh` exits 0 with all 5 cases PASS.
- [x] AC-1.8 — Old hooks and tests removed: `[ ! -f hooks/validate-bash-no-background.sh ] && [ ! -f hooks/validate-bash-readonly.sh ] && [ ! -f .claude/hooks/validate-bash-no-background.sh ] && [ ! -f .claude/hooks/validate-bash-readonly.sh ] && [ ! -f tests/test-validate-bash-no-background.sh ] && [ ! -f tests/test-validate-bash-readonly.sh ]`.
- [x] AC-1.9 — `tests/run-all.sh` registers the 2 new test files: `grep -F 'test-inject-bash-timeout' tests/run-all.sh && grep -F 'test-verify-response-validate' tests/run-all.sh`. Old registrations removed: `! grep -F 'test-validate-bash-no-background' tests/run-all.sh && ! grep -F 'test-validate-bash-readonly' tests/run-all.sh`. Part1 canary registration retained.
- [x] AC-1.10 — `grep -F 'Verifier-cannot-run is a verification FAIL' CLAUDE.md` returns 1+ line (rule retained from original Phase 1.7).
- [x] AC-1.11 — Full test suite (resolve `$FULL_TEST_CMD` from config) passes against the captured baseline; net change is approximately -23 PASS lines (validate-bash-* removed) +12 PASS lines (inject-bash-timeout + verify-response-validate added) = ~-11 PASS lines vs. the original Phase 1 baseline of 2056/2056. Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`.

### Dependencies

- None. This phase is self-contained.

---

## Phase 2 — Migrate `/run-plan` Phase 3 verifier dispatch + Layer 3 invocation

### Goal

Update `/run-plan` SKILL.md Phase 3 to:
1. Add explicit `subagent_type: "verifier"` to the `Agent`-tool dispatch (worktree mode + delegate mode).
2. After the dispatch returns, pipe the verifier's response through `bash $CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh`. On exit 1: STOP, write tracker entry, halt the pipeline, emit the verbatim Failure Protocol message.
3. Also detect agent-timeout-exceeded (existing 45-min rule, line ~1275-1280) as a co-trigger of the same Failure Protocol.

Bump `skills/run-plan/SKILL.md` `metadata.version`. Mirror via `scripts/mirror-skill.sh`.

### Work Items

- [ ] 2.1 — **Edit `skills/run-plan/SKILL.md` Phase 3 dispatch protocol** (`### Worktree mode verification` section, currently lines ~1355-1454). At each `Agent`-tool dispatch site (worktree mode + delegate mode), add explicit `subagent_type: "verifier"`. Insert a verbatim instruction block above the dispatch description:

  > **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The verifier agent definition lives at `.claude/agents/verifier.md` — `tools: Read, Grep, Glob, Bash, Edit, Write`; frontmatter PreToolUse hook (`inject-bash-timeout.sh`) auto-extends every Bash call's timeout to 600000 ms (10 min) so the bg+Monitor recovery reflex never engages. The verifier CANNOT dispatch sub-subagents — fix-agent dispatch (Phase 3 step 3 "fresh fix agent") stays at the orchestrator level. If the dispatch returns "no such agent" or equivalent, the verifier agent file is missing — STOP and run `/update-zskills` (Phase 5 of the verifier-agent-fix plan teaches it to install `.claude/agents/verifier.md`).

- [ ] 2.2 — **Add the Layer 3 invocation block.** Immediately after the dispatch returns (and before any tracker write or commit), pipe `$VERIFIER_RESPONSE` through `verify-response-validate.sh`. Insert as a new subsection `### Failure Protocol — verifier response validation` immediately AFTER the `### Worktree mode verification` numbered list. Body verbatim:

  > **Failure Protocol — verifier response validation (Layer 3).**
  >
  > **Detection runs immediately after the verifier `Agent` dispatch returns**, before any tracker write or commit:
  >
  > ```bash
  > printf '%s' "$VERIFIER_RESPONSE" | bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"
  > VALIDATE_EXIT=$?
  > ```
  >
  > The script (sourced from `hooks/verify-response-validate.sh` at zskills source; installed by `/update-zskills` Step C) checks:
  > - **Stalled-string trigger** — case-insensitive substring match of any of 7 whitelisted phrases against the LAST 10 LINES of the response (`let me wait for the monitor`, `tests are running. let me wait`, `monitor will signal`, `monitor to signal`, `still searching. let me wait`, `waiting on bashoutput`, `polling bashoutput`).
  > - **Min-byte threshold** — response < 200 bytes is treated as empty/stub.
  >
  > Exit 0 = PASS (proceed to tracker write + commit). Exit 1 = FAIL — read stderr to see which pattern or threshold fired.
  >
  > **AND** detect agent-timeout-exceeded: if the dispatch took longer than 45 minutes (existing rule, line ~1275-1280), treat as failed.
  >
  > **On detection (`VALIDATE_EXIT=1` OR timeout):** STOP. Do NOT write the verification step marker. Do NOT proceed to Phase 3.5 plan-drift correction. Do NOT proceed to Phase 4 commit. Emit the verbatim STOP message:
  >
  > ```
  > STOP: verifier returned without meaningful results.
  >
  > $(cat /tmp/last-validate-stderr)
  >
  > This is a verification FAIL, not a routing decision.
  >
  > Failure Protocol:
  > 1. Roll back any uncommitted phase work in <worktree-path>
  >    (git status; user-driven cleanup).
  > 2. Tracker entry: requires.verify-changes.<TRACKING_ID> stays unfulfilled.
  > 3. If you just installed the verifier agent (this is the first
  >    dispatch of the session post-install), restart Claude Code (or
  >    open a new session) before re-dispatching — `.claude/agents/`
  >    is auto-discovered ONLY at session start (per
  >    code.claude.com/docs/en/sub-agents priority table). There is
  >    no in-session reload command; `/agents reload` does not exist.
  > 4. Halt the pipeline. Do not auto-retry. Re-dispatch only after
  >    surfacing the failure and confirming the verifier agent file is
  >    installed (.claude/agents/verifier.md exists; bash
  >    $CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh < /dev/null
  >    exits 0).
  > ```
  >
  > **Inline self-verification is NOT acceptable recovery.** Per CLAUDE.md ## Verifier-cannot-run rule.
  >
  > **No automatic re-dispatch.** Re-dispatching with the same agent type hits the same wall.

- [ ] 2.3 — **Insert the dispatcher-attribution clarifier** at the "fresh fix agent" branch (Phase 3 step 3, lines ~1441-1454). Verbatim:

  > **Dispatcher: the orchestrator (top-level `/run-plan`), not the verifier subagent.** The verifier's tool allowlist excludes `Agent`; sub-subagent dispatch is categorically unavailable per https://code.claude.com/docs/en/sub-agents. The verifier reports failed-AC findings back; the orchestrator dispatches the fresh fix agent.

- [ ] 2.4 — **Bump `skills/run-plan/SKILL.md` `metadata.version`.** Recompute via `bash scripts/skill-content-hash.sh skills/run-plan` and replace with `YYYY.MM.DD+HHHHHH`. Verify via `bash scripts/skill-version-stage-check.sh`.

- [ ] 2.5 — **Mirror `skills/run-plan/` to `.claude/skills/run-plan/`** via `bash scripts/mirror-skill.sh run-plan`. Verify byte-equivalence.

### Design & Constraints

- **Layer 3 is invoked from the orchestrator** — where the dispatch returns. NOT from the verifier (the verifier already failed).
- **The 45-min agent timeout rule (existing line ~1275-1280) is preserved** as a co-trigger of the same Failure Protocol.
- **PR #148 prose warnings stay** — defense-in-depth.
- **`metadata.version` bump is mandatory** per SKILL_VERSIONING enforcement (PR #175).
- **Single PR, ordered commits — no mid-plan merge.** Phase 2's commit references `subagent_type: "verifier"` against the agent file landed in Phase 1's commit. Both ship in the same PR.
- **Commit boundary (Phase 2):** single commit. Files: `skills/run-plan/SKILL.md` (dispatch shape + Failure Protocol section + dispatcher-attribution clarifier + `metadata.version` bump), `.claude/skills/run-plan/SKILL.md` (mirror).

### Acceptance Criteria

- [ ] AC-2.1 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/run-plan/SKILL.md` returns ≥ 2 (worktree-mode dispatch + delegate-mode dispatch).
- [ ] AC-2.2 — `grep -F 'Failure Protocol — verifier response validation' skills/run-plan/SKILL.md` returns 1 line.
- [ ] AC-2.3 — `grep -F 'verify-response-validate.sh' skills/run-plan/SKILL.md` returns 1+ line (the script invocation).
- [ ] AC-2.4 — `grep -F 'STOP: verifier returned without meaningful results' skills/run-plan/SKILL.md` returns 1+ line.
- [ ] AC-2.5 — Dispatcher-attribution clarifier (D1) is in the SKILL.md verbatim: `grep -F 'Dispatcher: the orchestrator (top-level \`/run-plan\`), not the verifier subagent' skills/run-plan/SKILL.md` returns 1 line.
- [ ] AC-2.6 — `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC-2.7 — Staged `metadata.version` matches `YYYY.MM.DD+HHHHHH` shape; date is today (`TZ=America/New_York date +%Y.%m.%d`); hash is 6 lowercase hex chars.
- [ ] AC-2.8 — `diff -rq skills/run-plan/ .claude/skills/run-plan/` returns no output.
- [ ] AC-2.9 — Full test suite passes; zero new failures vs. baseline.

### Dependencies

- Phase 1 must be complete (`.claude/agents/verifier.md`, `hooks/verify-response-validate.sh` exist).

---

## Phase 3 — Migrate `/commit`, `/fix-issues`, `/do`, `/verify-changes` (4 skills, same pattern)

### Goal

Apply the Phase 2 pattern uniformly to the 4 other verifier-dispatching skills:
1. Add explicit `subagent_type: "verifier"` at every `Agent`-tool dispatch site.
2. After the dispatch returns, pipe `$VERIFIER_RESPONSE` through `verify-response-validate.sh`. On exit 1, surface a per-skill STOP message and halt that skill's flow.
3. Bump each skill's `metadata.version`. Mirror each.

`/commit` Phase 5 step 3 dispatches `subagent_type: "verifier"` (NOT `"commit-reviewer"` — that agent was dropped per D''). The "review only, do not mutate state" constraint is enforced by prose preamble in the dispatch prompt; if a future incident proves prose insufficient, surface the bug.

### Work Items

- [ ] 3.1 — **Edit `skills/commit/SKILL.md` Phase 5 step 3** (currently lines ~274-299). At the dispatch site, add explicit `subagent_type: "verifier"` AND a prose preamble in the dispatch prompt:

  > **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The dispatch prompt MUST include the verbatim preamble: `"You are reviewing the staged diff. Read-only review — do NOT git stash, checkout, restore, reset, add, rm, commit, push, merge, rebase, cherry-pick, revert, tag, or branch -D. Do NOT edit, write, or delete any file. Read the diff, run any read-only checks (git diff, git log, git show), and report concerns or approve."` After the dispatch returns, pipe `$VERIFIER_RESPONSE` through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`; on exit 1 STOP without committing.

  Keep the existing read-only prose verbatim — defense-in-depth + downstream documentation.

- [ ] 3.2 — **Bump `skills/commit/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.3 — **Edit `skills/fix-issues/SKILL.md` `### Dispatch protocol` section** (currently lines ~950-980). At the per-issue verification dispatch site, add explicit `subagent_type: "verifier"` AND the Layer 3 invocation. Verbatim block:

  > **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. After the dispatch returns, pipe `$VERIFIER_RESPONSE` through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`; on exit 1 STOP that issue's flow and surface to the user. Per Anthropic's documented design, the verifier cannot dispatch sub-subagents — for the per-issue case this is fine: each verifier handles one issue's worktree. If a verification reveals a fix is needed, surface to the user (or to `/run-plan` if dispatched by it); the orchestrator dispatches any fix agent.

- [ ] 3.4 — **Bump `skills/fix-issues/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.5 — **Edit `skills/do/SKILL.md` Phase 3 verification dispatches** (currently lines ~708-754). Two distinct shapes — both gain explicit `subagent_type: "verifier"` AND the Layer 3 invocation:
  - **Code-changes path** (line ~744): "dispatch a separate verification agent running `/verify-changes`" → `subagent_type: "verifier"`; pipe response through `verify-response-validate.sh`.
  - **Content-only path** (line ~717): "dispatch a separate verification agent" → `subagent_type: "verifier"` + same Layer 3 invocation. The verifier's allowlist (`Read, Grep, Glob, Bash, Edit, Write`) is sufficient for content review (Read + Grep cover the main path); the prose preamble keeps it from running tests.

- [ ] 3.6 — **Bump `skills/do/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.7 — **Edit `skills/verify-changes/SKILL.md` `### Dispatch protocol` section** (currently lines 31-67). The canonical verifier IS itself a dispatcher — it dispatches sub-agents for diff/coverage/manual reviews when it has the `Agent` tool. After this plan lands, `/verify-changes` is most often invoked BY the new `verifier` subagent, which lacks `Agent` — so the inline fallback path (`:43-61`) is the live path. Update to:

  > **Dispatch shape (top-level invocation).** When `/verify-changes` is invoked at the top level AND the orchestrator has the `Agent` tool, dispatched sub-agents use `subagent_type: "verifier"`; pipe each agent's response through `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh"`; on exit 1 STOP the sub-flow. When invoked from within a `verifier` subagent (the typical case after this plan lands), the `Agent` tool is unavailable categorically — fall through to the inline path (`:43-61`). Document the freshness mode in the verification report ("multi-agent" / "single-context fresh-subagent" / "inline self-review").

  Add the explicit `subagent_type: "verifier"` parameter at the top-level dispatch site(s) within `/verify-changes` itself.

- [ ] 3.8 — **Bump `skills/verify-changes/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.9 — **Audit:** verify NO skill outside the migration scope ({`commit`, `fix-issues`, `do`, `verify-changes`, `run-plan`}) was modified across the entire feature branch. Use a **branch-range** diff: `git diff --name-only main...HEAD -- skills/ | grep -v -E '^skills/(commit|fix-issues|do|verify-changes|run-plan)/'` returns no output.

### Design & Constraints

- **Bundle all 4 remaining skills in this phase, not staged.** Per `feedback_dont_defer_hole_closure.md`. Coherence > smaller PRs.
- **All 4 skills use `subagent_type: "verifier"`** — single agent definition, single behavior. The /commit read-only constraint is encoded in the dispatch-prompt preamble (drop-in for the dropped `commit-reviewer.md`).
- **All 4 skills invoke `verify-response-validate.sh`** — Layer 3 is universal across the 5 sites (Phase 2 wires the 5th).
- **Each modified skill bumps `metadata.version`.** 4 bumps in this phase + 1 in Phase 2 + 1 in Phase 5 = 6 total.
- **`/verify-changes` modification is to the dispatch protocol prose (line 31-67), not the inline fallback.**
- **`/verify-changes` freshness-mode reporting is mandatory** when invoked from inside a `verifier` subagent. AC-3.10 asserts this.
- **PR #148 prose warnings stay.** Defense-in-depth.
- **Single PR — Phase 3 commits ship on the same feature branch as Phases 1, 2.**
- **Commit boundary (Phase 3):** four ordered commits — one per migrated skill — each pairs the source SKILL.md edit + the `metadata.version` bump + the mirror under `.claude/skills/`.
  - Commit 3-A: `skills/commit/SKILL.md`, `.claude/skills/commit/SKILL.md`.
  - Commit 3-B: `skills/fix-issues/SKILL.md`, `.claude/skills/fix-issues/SKILL.md`.
  - Commit 3-C: `skills/do/SKILL.md`, `.claude/skills/do/SKILL.md`.
  - Commit 3-D: `skills/verify-changes/SKILL.md`, `.claude/skills/verify-changes/SKILL.md`.

### Acceptance Criteria

- [ ] AC-3.1 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/commit/SKILL.md` returns ≥ 1. (NOTE: NOT `"commit-reviewer"` — that agent was dropped per D''.)
- [ ] AC-3.2 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/fix-issues/SKILL.md` returns ≥ 1.
- [ ] AC-3.3 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/do/SKILL.md` returns ≥ 2.
- [ ] AC-3.4 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/verify-changes/SKILL.md` returns ≥ 1.
- [ ] AC-3.5 — All 4 skills invoke the Layer 3 script: `for s in commit fix-issues do verify-changes; do grep -qF 'verify-response-validate.sh' "skills/$s/SKILL.md" || { echo "missing in $s"; exit 1; }; done` exits 0.
- [ ] AC-3.6 — `/commit` dispatch prompt contains the read-only preamble: `grep -F 'Read-only review — do NOT git stash' skills/commit/SKILL.md` returns 1+ line.
- [ ] AC-3.7 — Per-skill `metadata.version` freshness across all 4 staged skills: `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC-3.8 — `for s in commit fix-issues do verify-changes; do diff -rq skills/$s/ .claude/skills/$s/ || exit 1; done` returns no output.
- [ ] AC-3.9 — Out-of-scope-skills audit uses the branch range: `git diff --name-only main...HEAD -- skills/ | grep -v -E '^skills/(commit|fix-issues|do|verify-changes|run-plan)/'` returns no output.
- [ ] AC-3.10 — `/verify-changes` SKILL.md documents the freshness-mode-reporting requirement: `grep -F 'multi-agent' skills/verify-changes/SKILL.md && grep -F 'single-context fresh-subagent' skills/verify-changes/SKILL.md && grep -F 'inline self-review' skills/verify-changes/SKILL.md` returns at least one line per phrase.
- [ ] AC-3.11 — PR #148 prose warning still appears in each of the 4 originally-warned skills: `for s in run-plan do fix-issues verify-changes; do grep -qF 'run_in_background' skills/$s/SKILL.md || { echo "missing in $s"; exit 1; }; done` exits 0.
- [ ] AC-3.12 — Full test suite passes; zero new failures vs. baseline.

### Dependencies

- Phase 1 must be complete (`.claude/agents/verifier.md`, `hooks/verify-response-validate.sh` exist).
- Phase 2 must be complete (run-plan migration is the model the other 4 follow).

---

## Phase 4 — Canaries: tools-allowlist, timeout-injection, failure-protocol script

### Goal

Add 3 canary tests proving the D'' structural fix holds end-to-end. Each canary is a sandbox-based, registered test under `tests/`, runnable via `tests/run-all.sh`.

The original Phase 4 had 4 canaries; the bg-rejection canary is dropped (Layer 2 no longer exists). The replacement set is:

1. **Tools-allowlist via fixture** — already shipped as `canary-verifier-agent-discovery-part1.sh` + `part2.sh` (kept from original Phase 1). Asserts a fixture subagent (`canary-readonly.md`, tools: `Read` only) cannot call Bash. Verifies the harness honors the allowlist.
2. **Timeout-injection works** — dispatches `subagent_type: "verifier"` with a Bash tool call that has no `timeout` field; asserts the executed Bash had `timeout: 600000` injected by Layer 0.
3. **Layer 3 script behavior against synthetic responses** — runs `verify-response-validate.sh` with stalled and clean fixtures, asserts the exit code distribution.

### Work Items

- [ ] 4.1 — **Canary 1 — Tools-allowlist (already shipped, kept).** `tests/canary-verifier-agent-discovery-part1.sh` + `tests/canary-verifier-agent-discovery-part2.sh`. Manual two-script flow per original Phase 1.1 (auto-discovery requires session restart). CI registers part1 only. The canary is structural-allowlist proof for the harness — independent of D'' choice — and provides confidence that subagents loaded from `.claude/agents/` honor their `tools:` field.

- [ ] 4.2 — **Canary 2 — Layer 0 timeout injection works at dispatch time.** `tests/canary-verifier-timeout-injection.sh`.

  **Probe step (FIRST — converts silent-pass into loud assertion failure).** Dispatch `Agent(subagent_type: "verifier", prompt: "Reply with literal string CANARY-PROBE-OK and nothing else.")`. Assert the response contains the literal token `CANARY-PROBE-OK`. If absent, exit 0 with the verbatim line `agent not yet discovered — fresh session required (.claude/agents/ auto-discovers at session start; restart Claude Code or open a new session, then re-run this canary)` printed to stdout. Loud, not silent.

  **Real assertion (after probe passes).** Dispatch `subagent_type: "verifier"` with a prompt that asks the verifier to run a Bash call which writes the JSON of its actual `tool_input` to a sentinel file, e.g.:

  > "Run a Bash call with no `timeout` parameter that captures the stdin sent to a recording wrapper. Specifically: `echo \"$BASH_TOOL_INPUT_JSON\" > /tmp/zskills-canary-injection.json` if such a variable exists, otherwise inspect by running `set | grep TIMEOUT` and report what you observe about the timeout value."

  This canary is harder to make deterministic in pure shell because we cannot directly observe what `tool_input` the harness presents to Bash. **Acceptable simplification:** unit-test the hook script in isolation (already done by `test-inject-bash-timeout.sh`), AND smoke-test that a verifier-subagent dispatch completes successfully on a Bash call that would have timed out at 120s default — e.g., `sleep 130 && echo done`. Assert the dispatch returns `done` (or a long-enough partial transcript) within 600s. If the harness IS injecting timeout, this completes; if not, the call times out at 120s and the canary fails.

- [ ] 4.3 — **Canary 3 — `verify-response-validate.sh` against synthetic inputs.** `tests/canary-verify-response-validate.sh`. Pure script-level test (no live subagent dispatch needed — the script is independently testable). Sub-cases:

  - **Sub-case A** — clean response (≥200 bytes, no stalled patterns) → exit 0.
  - **Sub-case B** — stalled phrase in last 10 lines → exit 1, stderr names the matched phrase.
  - **Sub-case C** — stalled phrase in EARLIER lines but recovered tail → exit 0 (last-10-lines anchor).
  - **Sub-case D** — sub-200-byte response → exit 1, stderr names the threshold.
  - **Sub-case E** — empty response → exit 1.
  - **Sub-case F** (threshold-calibration positive cases per N3) — three realistic ≥200-byte "tests skipped" attestations, all expected exit 0:
    - F-a: "Tests: skipped — no test infra detected. TEST_MODE=skipped per zskills-config.json. Phase scope is markdown-only (CLAUDE.md edits + plan refinement). No code surface to exercise. Verification consists of grep audits of section anchors — passed."
    - F-b: "Tests: skipped — phase scope is content-only (CHANGELOG entry + frontmatter status update). I read the diff; CHANGELOG entry resolves to today's date and references the correct issues. PLAN_INDEX.md move is correct. No assertion failures."
    - F-c: "Tests: skipped — TEST_MODE=skipped per zskills-config.json. The phase touches only references/ docs; the test config explicitly excludes references/ from the test surface. Verified the markdown renders without warnings via mdformat --check."
  - **Sub-case G** (threshold-calibration negative cases) — three stub responses, all expected exit 1 with stderr referencing the threshold:
    - G-a: "ok done" (7 bytes)  <!-- Auto-corrected 2026-05-03: was 8, arithmetic says 7 -->
    - G-b: "verified" (8 bytes)
    - G-c: "Tests: passed" (13 bytes)

  **Note on overlap with `test-verify-response-validate.sh`:** Phase 1's unit test covers the 5-case core. This canary extends with the threshold-calibration matrix (sub-cases F + G) so the threshold cutoff is example-driven, not arbitrary. Both are registered in `tests/run-all.sh`.

- [ ] 4.4 — **Register canaries 2 and 3 in `tests/run-all.sh`** via `run_suite` lines. Canary 1 (part1) is already registered.

### Design & Constraints

- **Sandbox-based** — each canary uses its own `WORK_BASE="/tmp/zskills-tests/$(basename "$REPO_ROOT")/<suite>-cases"`.
- **No live `/run-plan` cron in canaries.**
- **No `kill -9` / `killall` / `pkill` / `fuser -k`.**
- **Capture canary output to `/tmp/zskills-tests/$(basename "$(pwd)")/<canary-name>.log`**, not piped.
- **Commit boundary (Phase 4):** single commit. Files: `tests/canary-verifier-timeout-injection.sh` (new), `tests/canary-verify-response-validate.sh` (new), `tests/run-all.sh` (2 new `run_suite` lines).

### Acceptance Criteria

- [ ] AC-4.1 — `bash tests/canary-verifier-agent-discovery-part1.sh` exits 0 with PASS (already shipped).
- [ ] AC-4.2 — `bash tests/canary-verifier-timeout-injection.sh` exits 0 with all assertions PASS (probe-step gating + real assertion).
- [ ] AC-4.3 — `bash tests/canary-verify-response-validate.sh` exits 0 with all sub-cases A-G PASS (5 baseline + 3 positive threshold-calibration + 3 negative).
- [ ] AC-4.4 — `grep -F 'canary-verifier-timeout-injection' tests/run-all.sh && grep -F 'canary-verify-response-validate' tests/run-all.sh` — both return 1+ line each.
- [ ] AC-4.5 — Full test suite passes; zero new failures vs. baseline.

### Dependencies

- Phases 1, 2, 3 must be complete.

---

## Phase 5 — `/update-zskills` install path for verifier.md + 2 new hooks

### Goal

**Extend `/update-zskills` Step C ("Fill hook gaps")** at `skills/update-zskills/SKILL.md:816-836`. The extension does TWO things in the same step (NOT a sibling step):
1. The hook-copy loop iterates an extended source list that includes the new `inject-bash-timeout.sh` and `verify-response-validate.sh` alongside the existing `block-*` and `warn-config-drift.sh` hooks.
2. A new agent-copy block immediately after the hook copy iterates `$PORTABLE/.claude/agents/*.md` and copies missing/changed ones to the consumer's `.claude/agents/`.

Step C's narrative changes from "Fill hook gaps" to "Fill hook + agent gaps". Audit step in Step 3's summary lists installed agents alongside hooks. End-to-end: a fresh consumer install picks up the verifier agent definition and both hook scripts; the structural defense is live after a session restart.

### Work Items

- [ ] 5.1 — **Edit `skills/update-zskills/SKILL.md` Step C** (currently lines ~816-836). Two extensions:

  **Extension 1 — extend the hook list** to include `inject-bash-timeout.sh` and `verify-response-validate.sh` (sister of `block-unsafe-generic.sh` etc.). Both install to `$PROJECT_DIR/.claude/hooks/`. No new directory, no new install pattern.

  **Extension 2 — agent-copy block** immediately after the hook copy:

  > **Custom subagent definitions.** After hook copy, copy missing or changed agent definitions from `$PORTABLE/.claude/agents/*.md` to `$PROJECT_DIR/.claude/agents/`. `cp -a` preserves mode bits + mtime. The agent frontmatter references `$CLAUDE_PROJECT_DIR/.claude/hooks/inject-bash-timeout.sh` — that path is fixed, so the hook-copy step (above) is a hard prerequisite.
  >
  > ```bash
  > if [ -d "$PORTABLE/.claude/agents" ]; then
  >   mkdir -p .claude/agents
  >   for src in "$PORTABLE/.claude/agents"/*.md; do
  >     [ -e "$src" ] || continue
  >     name=$(basename "$src")
  >     dst=".claude/agents/$name"
  >     if [ ! -f "$dst" ]; then
  >       cp -a "$src" "$dst" && echo "Installed agent: $name"
  >     elif ! cmp -s "$src" "$dst"; then
  >       cp -a "$src" "$dst" && echo "Updated agent: $name"
  >     fi
  >   done
  >   echo "WARN: agent definitions auto-discover at session start. Restart Claude Code (or open a new session) before invoking verifier-using skills (/run-plan, /commit, /fix-issues, /do, /verify-changes). There is no in-session reload command."
  > fi
  > ```
  >
  > **No settings.json wiring needed for agents.** Auto-discovered.
  > **Bash regex parse only — no `jq`.** (Hook scripts may use Python; `inject-bash-timeout.sh` does, per zskills convention exemption for JSON round-trip.)

- [ ] 5.2 — **Add audit/diff step** in Step 3's install summary:

  > Installed agents:
  > - verifier (from .claude/agents/verifier.md, Layer 0 timeout-injection hook)
  >
  > Installed hook scripts (D'' structural defense):
  > - .claude/hooks/inject-bash-timeout.sh (Layer 0 — auto-extends Bash timeout to 600000 ms for verifier subagent)
  > - .claude/hooks/verify-response-validate.sh (Layer 3 — universal verifier-response failure-protocol primitive)
  >
  > Drift check: each .md is byte-equivalent to source.
  > Drift check: each hook script is byte-equivalent to source.

- [ ] 5.3 — **Bump `skills/update-zskills/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 5.4 — **Add a test for the install path.** `tests/test-update-zskills-agent-install.sh`. Sandbox-based:
  - Set up fake consumer repo at `$WORK_BASE/consumer/` with empty `.claude/`.
  - Set `$PORTABLE` to point at a sandbox mirror containing `.claude/agents/verifier.md` + the two new hook scripts.
  - Run the Step C install flow against the sandbox.
  - Assert: `[ -f "$WORK_BASE/consumer/.claude/agents/verifier.md" ]`, `[ -x "$WORK_BASE/consumer/.claude/hooks/inject-bash-timeout.sh" ]`, `[ -x "$WORK_BASE/consumer/.claude/hooks/verify-response-validate.sh" ]`. Assert `[ ! -f "$WORK_BASE/consumer/.claude/agents/commit-reviewer.md" ]` (D'' dropped this agent). Assert `[ ! -d "$WORK_BASE/consumer/.claude/scripts" ]`.
  - Assert byte-equivalence: `cmp -s "$PORTABLE/.claude/agents/verifier.md" "$WORK_BASE/consumer/.claude/agents/verifier.md"`.
  - Re-run idempotently; no spurious "Updated" lines.
  - Modify consumer's `verifier.md`; re-run; assert "Updated agent: verifier.md" line appears.

- [ ] 5.5 — **Register the new test in `tests/run-all.sh`** via `run_suite "agent-install" "tests/test-update-zskills-agent-install.sh"`.

- [ ] 5.6 — **Mirror `skills/update-zskills/`** via `bash scripts/mirror-skill.sh update-zskills`.

### Design & Constraints

- **`/update-zskills` is the only consumer-facing install path.**
- **Idempotent.** `cmp -s` gates the copy.
- **Consumer-customization handling:** if a consumer edits `.claude/agents/verifier.md`, the next install OVERWRITES with source. Document in extended Step C prose.
- **No `settings.json` modifications in this phase.**
- **Hook scripts: bash + Python (no jq).** `inject-bash-timeout.sh` uses Python; this is documented in its header comment.
- **Commit boundary (Phase 5):** single commit. Files: `skills/update-zskills/SKILL.md` (Step C extension + audit step + version bump), `.claude/skills/update-zskills/SKILL.md` (mirror), `tests/test-update-zskills-agent-install.sh` (new), `tests/run-all.sh` (1 new line).

### Acceptance Criteria

- [ ] AC-5.1 — Step C is **extended in place**: existing heading still present AND section now contains an agent-copy sub-block AND references the 2 new hook scripts. Verify: `grep -F '#### Step C' skills/update-zskills/SKILL.md` returns 1+ line; `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F '.claude/agents'` returns 1+ line; `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F 'inject-bash-timeout.sh'` returns 1+ line; `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F 'verify-response-validate.sh'` returns 1+ line.
- [ ] AC-5.2 — Auto-discovery WARN line is present: `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F 'WARN: agent definitions auto-discover at session start'` returns 1 line. WARN does NOT mention the fictional `/agents reload`: `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F '/agents reload'` returns no output OR only the explicit "no in-session reload command" disclaimer.
- [ ] AC-5.3 — `bash tests/test-update-zskills-agent-install.sh` exits 0 with all sub-cases PASS.
- [ ] AC-5.4 — `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC-5.5 — `diff -rq skills/update-zskills/ .claude/skills/update-zskills/` returns no output.
- [ ] AC-5.6 — `grep -F 'test-update-zskills-agent-install' tests/run-all.sh` returns 1+ line.
- [ ] AC-5.7 — End-to-end manual install verification: dispatch `/update-zskills` against sandbox `$PORTABLE` in scratch consumer dir. Confirm `.claude/agents/verifier.md`, `.claude/hooks/inject-bash-timeout.sh`, `.claude/hooks/verify-response-validate.sh` all land in scratch dir AND WARN line appears. Capture transcript to `/tmp/zskills-tests/$(basename "$(pwd)")/manual-install.log`.
- [ ] AC-5.8 — Hook scripts install to `.claude/hooks/`, NOT `.claude/scripts/`: `[ -f .claude/hooks/inject-bash-timeout.sh ] && [ -f .claude/hooks/verify-response-validate.sh ] && [ ! -d .claude/scripts ]`.
- [ ] AC-5.9 — `commit-reviewer.md` does NOT install (D'' dropped it): `[ ! -f $SCRATCH/.claude/agents/commit-reviewer.md ]`.
- [ ] AC-5.10 — Full test suite passes; zero new failures vs. baseline.

### Dependencies

- Phases 1, 2, 3, 4 must be complete.

---

## Phase 6 — CHANGELOG, file Anthropic issue, plan completion

### Goal

Finalize documentation: confirm CLAUDE.md rule from Phase 1 is in place; add a CHANGELOG entry under today's date; verify every modified skill's `metadata.version` is fresh; verify the full plan-level closure of #176 and #180; **file an upstream Anthropic issue documenting the bg+Monitor harness hang** so the underlying primitive is on the vendor's radar (per CLAUDE.md "skill-framework repo — surface bugs, don't patch" rule). Plan-completion bookkeeping.

The original Phase 6 included a follow-up issue to "extract failure-protocol to shared library." That issue is **dropped** — D'' already does the extraction (`verify-response-validate.sh` IS the shared library, applied to all 5 sites in Phases 2 and 3).

### Work Items

- [ ] 6.1 — **Verify CLAUDE.md rule** from Phase 1.7 is in place: `grep -F 'Verifier-cannot-run is a verification FAIL' CLAUDE.md`. If not, add it now.

- [ ] 6.2 — **Add CHANGELOG.md entry** under today's date (`TZ=America/New_York date +%Y-%m-%d`). Use **schematic placeholders only** in the plan source. Verbatim shape:

  > ## YYYY-MM-DD
  >
  > - **Verifier subagent — D'' structural defense.** Replaced the prose-only `run_in_background: true` warning (PR #148) with a Claude Code custom-subagent definition at `.claude/agents/verifier.md` plus two new hook scripts. **Layer 0 (root-cause fix):** `hooks/inject-bash-timeout.sh` is a frontmatter PreToolUse hook on Bash that auto-extends every Bash call's `timeout` to 600000 ms (10 min) via the `updatedInput` envelope field — the 120s default that triggered the bg+Monitor recovery reflex no longer applies to verifier dispatches. **Layer 3 (universal failure-protocol primitive):** `hooks/verify-response-validate.sh` is a script that any verifier-dispatching skill pipes the verifier's response through (7-phrase stalled-string whitelist anchored to last 10 lines + 200-byte minimum-length signal). Five dispatch sites migrated to explicit `subagent_type: "verifier"` parameters AND the Layer 3 invocation: `/run-plan` Phase 3, `/commit` Phase 5 step 3, `/fix-issues` per-issue verification, `/do` Phase 3 (code + content paths), `/verify-changes` self-dispatch. `/update-zskills` Step C extended to install `.claude/agents/verifier.md` and the two hook scripts. CLAUDE.md gains "Verifier-cannot-run is a verification FAIL" rule. Closes #176, #180.

- [ ] 6.3 — **Verify all modified skills have fresh `metadata.version`**: `bash scripts/skill-version-stage-check.sh` exits 0.

- [ ] 6.4 — **Verify mirror dirs are byte-equivalent to source:**
  ```bash
  for s in run-plan commit fix-issues do verify-changes update-zskills; do
    diff -rq "skills/$s/" ".claude/skills/$s/" || exit 1
  done
  ```

- [ ] 6.5 — **Final acceptance verification — closure of #176 and #180:**
  - For #176: confirm `.claude/agents/verifier.md` exists with the `inject-bash-timeout.sh` PreToolUse hook reference; confirm `bash hooks/inject-bash-timeout.sh < /dev/null` returns a permissive allow envelope; confirm Phase 4 canary 2 (`canary-verifier-timeout-injection.sh`) PASSES.
  - For #180: confirm all 5 dispatch sites pipe verifier responses through `verify-response-validate.sh`; confirm Phase 4 canary 3 (`canary-verify-response-validate.sh`) PASSES with all sub-cases A-G.

- [ ] 6.6 — **Run the full test suite one final time.** Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`. Compare to baseline. Zero new failures.

- [ ] 6.7 — **File upstream Anthropic issue.** Open a GitHub issue against `anthropics/claude-code` (or the appropriate vendor channel) titled `Subagent dispatch hangs when bash backgrounding + Monitor/BashOutput poll` with body summarizing:
  - The failure mode: subagent backgrounds a Bash call, then polls BashOutput/Monitor; wake events do not deliver to one-shot subagent dispatches; the agent's turn ends waiting for a signal that never arrives.
  - The reproducer: any test suite whose runtime exceeds the default 120s tool timeout, dispatched via `subagent_type` with no Layer 0 timeout-injection.
  - The workaround we shipped: PreToolUse hook injecting `timeout: 600000` so the 120s timeout never trips. Surfaces the bug rather than silently routing around it.
  - Reference our PRs: #148 (the prose-only first attempt that failed mechanically), #175 (the failing canary case), #189 (this plan's structural fix).

  This is the "surface bugs, don't patch" closure for the vendor side — even though our local fix unblocks zskills, the harness primitive is still defective and other consumers will hit it.

- [ ] 6.8 — **Plan completion bookkeeping:** update plan frontmatter `status: complete` and `completed: <today>`; move plan from `plans/PLAN_INDEX.md` "Active" to "Complete" section.

### Design & Constraints

- **No new code in Phase 6.** Documentation, version verification, mirror verification, plan-completion bookkeeping, upstream issue.
- **CHANGELOG entry is for the entire plan** (one entry under today's date covering all 6 phases at the conceptual level).
- **#179 forbidden-literals scan compliance.** Plan text uses only schematic placeholders.
- **Drop the original Phase 6's "extract failure-protocol shared library" follow-up issue** — D'' already extracted it. Drop the original Phase 6's "structural Monitor/BashOutput 8th rule" follow-up — Layer 0 makes the 8th rule unnecessary (the bg+Monitor reflex no longer triggers from our dispatches).
- **Add the upstream Anthropic-issue work item** — required closure per CLAUDE.md "surface bugs, don't patch" rule.
- **Commit boundary (Phase 6):** single commit. Files: `CLAUDE.md` (idempotent verification), `CHANGELOG.md` (new entry), `plans/VERIFIER_AGENT_FIX.md` (frontmatter `status: complete`), `plans/PLAN_INDEX.md` (move).

### Acceptance Criteria

- [ ] AC-6.1 — `grep -F 'Verifier-cannot-run is a verification FAIL' CLAUDE.md` returns 1+ line.
- [ ] AC-6.2 — `head -20 CHANGELOG.md | grep -F 'Verifier subagent — D'\'\''' structural defense'` returns 1 line, AND the entry's date heading is today.
- [ ] AC-6.3 — `grep -F 'Closes #176, #180' CHANGELOG.md` returns 1+ line.
- [ ] AC-6.4 — `bash scripts/skill-version-stage-check.sh` exits 0 against the worktree state.
- [ ] AC-6.5 — `for s in run-plan commit fix-issues do verify-changes update-zskills; do diff -rq "skills/$s/" ".claude/skills/$s/" || exit 1; done` returns no output.
- [ ] AC-6.6 — All Phase 4 canaries PASS (`bash tests/canary-verifier-agent-discovery-part1.sh && bash tests/canary-verifier-timeout-injection.sh && bash tests/canary-verify-response-validate.sh` exits 0). (Manual part2 already passed 2026-05-03.)
- [ ] AC-6.7 — Full test suite passes; zero new failures vs. baseline.
- [ ] AC-6.8 — Plan frontmatter `status: complete`; `plans/PLAN_INDEX.md` lists the plan in the Complete section.
- [ ] AC-6.9 — `gh issue view 176` and `gh issue view 180` are ready to close (orchestrator closes with merge commit `Closes #176, #180`).
- [ ] AC-6.10 — Upstream Anthropic issue filed: provide the issue URL in the plan-completion report. The issue MUST reference (a) the failure mode, (b) the local D'' workaround, (c) PRs #148, #175, #189. (Skip with justification only if the vendor's issue tracker is not publicly accessible from this environment — record the would-be body in `plans/reports/VERIFIER_AGENT_FIX-anthropic-issue-draft.md`.)
- [ ] AC-6.11 — Forbidden-literals enforcement (#179): run `bash hooks/warn-config-drift.sh` against each modified plan/skill file as if just edited; assert no WARN line about forbidden literals fires.

### Dependencies

- Phases 1, 2, 3, 4, 5 must be complete.

---

## Drift Log

**2026-05-03 — D'' rework after Phase 1 land.** Phase 1 originally landed with the L1+L2 architecture (commit `89d1b57`): tools allowlist on `verifier.md` excluding `Monitor`/`BashOutput`; PreToolUse `validate-bash-no-background.sh` rejecting `run_in_background: true`; separate `commit-reviewer.md` agent with additional `validate-bash-readonly.sh`; manual canary PASSED 2026-05-03 against Claude Code 2.1.126.

User pushback + research surfaced that Layer 1 + Layer 2 were working AROUND the harness bug rather than addressing root cause. The bg+Monitor recovery reflex is *triggered* by the default 120s Bash-tool timeout. If we prevent the trigger (timeout never expires), the reflex never engages and we do not need to structurally restrict Monitor/BashOutput.

D'' refined architecture adopted:
- **Layer 0 added** — `hooks/inject-bash-timeout.sh`: PreToolUse hook that uses `updatedInput` to ensure every verifier Bash call gets `timeout: 600000` (10 min). Per Anthropic's PreToolUse documentation, hooks can modify tool inputs via the `updatedInput` field of the response envelope.
- **Layer 1 dropped** — verifier.md keeps the full tools allowlist (`Read, Grep, Glob, Bash, Edit, Write`); no exclusions on `Monitor`/`BashOutput`/etc.
- **Layer 2 dropped** — `validate-bash-no-background.sh` removed; redundant once Layer 0 prevents the trigger.
- **Layer 3 made script-based + universal** — `hooks/verify-response-validate.sh` is a callable script (not a hook) that all 5 dispatch sites pipe verifier responses through. Uniform failure-protocol detection across the whole verifier ecosystem, not just `/run-plan`. Future-extensible (add `PATTERNS_BACKEND_ERROR` etc. without touching call sites).
- **`commit-reviewer.md` dropped** — was solving a Layer-2-style read-only problem; with L2 dropped, the reviewer/verifier distinction has no structural carrier. /commit Phase 5 step 3 dispatches `subagent_type: "verifier"` with a prose preamble enforcing read-only review.
- **Original tools-allowlist canary kept** — `canary-verifier-agent-discovery-part1.sh`/`part2.sh` verify subagent auto-discovery + allowlist semantics, which are still load-bearing primitives for D''.

This rework lands as a single commit on the same PR branch (PR #189), pivoting Phase 1 in place. Phases 2-6 of the plan are rewritten in this same commit to reflect the D'' architecture; the original L1+L2 spec is preserved in commit history (commits `89d1b57`, `a71df7e`, `effe5c1`) for reviewer context. The original Plan Quality Round 1 + Round 2 findings (C1-C5, R1-R8, D1-D4, N1-N10) are preserved below as historical record — most still apply to D'' (the failure-protocol script formalizes C2/D3, the canary-discovery primitive is unchanged, the dispatcher-attribution clarifier carries over, etc.). The findings that no longer apply to D'' (anything keyed to the dropped `commit-reviewer.md` or the dropped `validate-bash-readonly.sh`, e.g., N6's adversarial-bypass cases) are tagged "superseded by D''" in the round history.

---

## Plan Quality

| Round | Reviewer Findings | Devil's Advocate Findings | After Dedup | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 13                | 10                        | 17          | 17       |
| 2     | 6                 | 7                         | 10          | 9        |
| 3 (D'' rework) | n/a — direct pivot per user pushback | n/a | n/a | n/a |

### Round History

**Round 1 (YYYY-MM-DD):**

Convergence findings (both reviewers): C1, C2, C3, C4, C5.
Reviewer-only: R1, R2, R3, R4, R5, R6, R7, R8.
DA-only: D1, D2, D3, D4.

Round-1 IDs (5C + 8R + 4D) sum to 17 distinct findings, all resolved (none Justified-not-fixed).

Restructuring in Round 1:
- Phase 1.8 dropped (R4); content folded into Phase 1 Design & Constraints.
- Phase 1 ACs renumbered: AC-1.9 (was references-doc check) removed; AC-1.10 → AC-1.9; AC-1.11 → AC-1.10.
- Phase 2 ACs added: AC-2.4b (no bare bashoutput), AC-2.4c (last-N-lines anchor), AC-2.4d (min-length signal), AC-2.4e (D1 dispatcher attribution).
- Phase 3 AC added: AC-3.10 (R3 freshness-mode reporting).
- Phase 5 ACs renumbered: AC-5.7 split into AC-5.7 (transcript verification) + AC-5.8 (path correctness); AC-5.8 (was full suite) → AC-5.9.
- Phase 6 AC added: AC-6.10 (D2 forbidden-literals scan).

**Round 2 (YYYY-MM-DD):**

Round-1-fix verifications: C1, C2, C4 confirmed; C3 surfaced new defect N1; C5 surfaced new defect N5; D3 surfaced new defect N3.

Round-2 new findings: N1 (HIGH — `/agents reload` is fictional in Claude Code 2.1.126), N2 (HIGH — `--agents` CLI flag takes inline JSON not file paths), N3 (MEDIUM — Failure Protocol scoped only to `/run-plan`; other 4 sites unprotected), N4 (MEDIUM — Plan Quality table contradiction; honest count is 17), N5 (MEDIUM — C5 footnote misstated current state), N6 (HIGH — readonly-bash hook bypassable via env-var prefix, &&, subshell, pipe), N7 (MEDIUM — AC-6.10 referenced non-existent forbidden-literals-scan script), N8 (MEDIUM — Phase 6.5 said "all 6 phrases", every other site says 7), N9 (LOW — whitelist enumeration has finite recall), N10 (LOW — Phase 1.4 case 6 used `\\n` literal that isn't a real newline).

Resolved this round (9): N1, N2, N3 (option a — scoped + follow-up issue work item 6.7), N4, N5, N6 (option b — word-boundary regex), N7, N8, N10.

Justified-not-fixed (1): N9 — deferred per round-2 review's allowance.

**Superseded by D'' (Round 3 rework):**
- **N3** (Failure Protocol scoped only to `/run-plan`) — RESOLVED DIRECTLY by D'': Layer 3 script `verify-response-validate.sh` is invoked from all 5 dispatch sites (Phases 2 + 3). The "extract to shared library" follow-up issue (work item 6.7) is dropped — extraction IS D''.
- **N6** (readonly-bash hook bypassable) — SUPERSEDED: `validate-bash-readonly.sh` was dropped along with `commit-reviewer.md`. The /commit read-only constraint is now in the dispatch-prompt preamble.
- **N9** (whitelist finite recall + 8th structural rule follow-up) — DROPPED: Layer 0 prevents the trigger that the 8th rule was guarding against.
- **C5 / N5 / AC-2.4 footnote** — partly superseded: the Failure Protocol section now references `verify-response-validate.sh` invocation rather than embedding the bash block inline; the section-anchor AC pattern still applies to the script-invocation block.
- **All findings keyed to `validate-bash-no-background.sh` test cases (N10)** — superseded: that script is dropped; replaced by `test-inject-bash-timeout.sh` with its own 7 cases including embedded-quotes round-trip.

**Round 3 (D'' rework — 2026-05-03):**

Direct user-pushback pivot, NOT a structured reviewer/DA round. Architectural change documented in Drift Log above. No new reviewer/DA findings collected before commit; the rework's correctness rests on:
- The hook-script unit tests (`test-inject-bash-timeout.sh` 7 cases, `test-verify-response-validate.sh` 5 cases) — all PASS.
- The full test suite passing (zero new failures vs. the original Phase 1 baseline 2056/2056, modulo the test-count delta from removing 2 old test files and adding 2 new ones).
- The original Phase 1 canary still PASSING — subagent auto-discovery + allowlist primitives are unchanged.
