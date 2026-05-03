---
title: Verifier Agent Fix
created: 2026-05-02
status: active
---

# Plan: Verifier Agent Fix

> **Landing mode: PR — single PR, ordered commits** — All 6 phases land as ordered commits in a single PR; **no per-phase merge to main** while the plan is in progress. Mid-plan windows where dispatchers reference `subagent_type:` parameters before the agent files exist (or vice versa) never become visible on `main`. This plan creates new agent definitions under `.claude/agents/`, two new validation scripts under `hooks/` (mirrored to `.claude/hooks/`), edits 5 source skills, extends `/update-zskills` Step C install + audit flow, and adds 4 canaries + test-suite registration. PR review is appropriate.

## Overview

Subagents dispatched by `/run-plan`, `/commit`, `/fix-issues`, `/do`, and `/verify-changes` reflexively reach for `Bash(run_in_background: true)` + `Monitor`/`BashOutput` polling when a foreground test invocation hits the default 120s Bash-tool timeout — wake events for backgrounded processes do not reliably deliver to one-shot subagent dispatches, so the wait never returns and the dispatch hangs at "Tests are running. Let me wait for the monitor." PR #148 (`2107db3`, 2026-05-01) added verbatim "DO NOT use `run_in_background: true`" prose warnings to four SKILL.md files; PR #175 (skill-versioning, 2026-05-02) demonstrated those warnings fail mechanically — every Phase 1-6 verifier dispatch hit the Monitor pattern. The orchestrator did inline verification across 5 of 7 phases, violating zskills's saved principle that "verifier-cannot-run is FAIL, never a routing decision" (`feedback_verifier_test_ungated.md`). Two GitHub issues filed against `zeveck/zskills-dev` 2026-05-02 capture the gap: **#176** (Monitor anti-pattern recurrence despite the verbatim warning) and **#180** (verifier-skipped silent pass — orchestrator logs a one-line note and proceeds instead of invoking the Failure Protocol).

This plan replaces the prose-only guardrail with a **structural** fix at three layers, all of which must hold simultaneously. Layer 1: a Claude Code custom subagent definition at `.claude/agents/verifier.md` with a `tools:` allowlist. Tool restriction is harness-enforced — the subagent cannot see or call tools outside the allowlist. Layer 2: because `Bash` itself must stay on the allowlist (the verifier runs tests + git), and `run_in_background: true` is a Bash *parameter* the allowlist cannot restrict, a frontmatter `PreToolUse` hook on `Bash` rejects any tool input where `run_in_background` is `true`. This is the canonical pattern from Anthropic's `db-reader` example (https://code.claude.com/docs/en/sub-agents), ported to bash regex (`BASH_REMATCH`) per zskills convention — no `jq`. Hook scripts live at source `hooks/validate-bash-no-background.sh` and `hooks/validate-bash-readonly.sh` and install to `.claude/hooks/` (existing convention — sister of `block-unsafe-generic.sh`, `block-agents.sh`, `warn-config-drift.sh`). Layer 3: a `/run-plan` Phase 3 failure-protocol clause that detects empty/stalled verifier returns and STOPs, emitting a tracker entry and halting the pipeline rather than logging a note and proceeding. Five dispatch sites (`/run-plan` Phase 3, `/commit` Phase 5 step 3, `/fix-issues` per-issue, `/do` Phase 3 code path, `/verify-changes` self-dispatch) gain explicit `subagent_type:` parameters at their `Agent`-tool dispatches. `/update-zskills` Step C is **extended** (not given a sibling step) to also copy `.claude/agents/<name>.md` files alongside the existing hook copy, so consumer repos receive the structural fix without manual setup. Source-of-truth count: `find skills -maxdepth 1 -mindepth 1 -type d -exec test -f '{}/SKILL.md' \; -print | wc -l` (count is derivation-driven, NOT pinned — re-count at execution time).

**Success criterion:** A fresh `/run-plan` invocation that dispatches a verification subagent for a long-running test suite (one whose runtime exceeds the default 120s Bash-tool timeout) **never hangs at "Tests are running. Let me wait for the monitor."** If the verifier fails for any other reason — including returning empty/no-results, missing the test-summary line, or exceeding the 45-min agent timeout — the orchestrator STOPs and invokes the Failure Protocol; it does NOT log a one-line note and proceed. Closes #176 and #180. PR #148's prose warnings stay in place as belt-and-suspenders (the structural fix is primary; prose is documentation). The `.claude/agents/verifier.md` file ships through `/update-zskills` so a fresh consumer install of zskills picks up the verifier agent definition automatically.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Decision, agent-definition authoring, hook script | 🟡 | `89d1b57` | Implemented + verified (2056/2056 tests). **Manual canary gate pending** — user runs `bash tests/canary-verifier-agent-discovery-part{1,2}.sh` (with Claude Code session restart between) to verify the structural-allowlist claim before Phase 2 commits dispatch sites. |
| 2 — Migrate `/run-plan` Phase 3 + add failure-protocol clause | ⬚ |        |       |
| 3 — Migrate `/commit`, `/fix-issues`, `/do`, `/verify-changes` | ⬚ |        |       |
| 4 — Canaries: agent discovery, hook block, sub-subagent denial, failure-protocol firing | ⬚ |        |       |
| 5 — `/update-zskills` install path + end-to-end consumer test | ⬚ |        |       |
| 6 — Documentation, CLAUDE.md, CHANGELOG, final verification | ⬚ |        |       |

---

## Phase 1 — Decision, agent-definition authoring, hook script

### Goal

Verify the Claude Code custom-agent semantics against a working canary BEFORE any skill prose changes. Author the verifier agent definition (`.claude/agents/verifier.md`), the commit-reviewer agent definition (`.claude/agents/commit-reviewer.md`), and the two `PreToolUse` hook scripts (`hooks/validate-bash-no-background.sh`, `hooks/validate-bash-readonly.sh` — installed to `.claude/hooks/`) the agent frontmatters reference. Encode the "verifier-cannot-run is FAIL" rule in CLAUDE.md. No source skill edits in this phase — this phase produces the artifacts the migration phases will reference.

### Work Items

- [ ] 1.1 — **Verify the structural-allowlist claim against current Claude Code.** The `--agents` CLI flag takes **inline JSON**, not file paths (verified: `claude --help` shows `--agents <json>` with example `'{"reviewer": {"description": "...", "prompt": "..."}}'`); and `.claude/agents/*.md` is **auto-discovered ONLY at session start** (priority 3 per `code.claude.com/docs/en/sub-agents`). Both routes preclude a single-process canary that drops a fixture file and dispatches it in the same session. The canonical canary is therefore a **two-script flow** — restart-gated, explicit, loud:

  - **Script 1 — `tests/canary-verifier-agent-discovery-part1.sh`:** writes the fixture agent file at `.claude/agents/canary-readonly.md` (tools: `Read` only — no Bash, no Edit) from a sandbox source under `tests/fixtures/canary-agents/canary-readonly.md`. On exit, prints to stdout the verbatim instruction:

    ```
    This canary requires a fresh Claude Code session — `.claude/agents/`
    is auto-discovered only at session start (priority 3, per
    code.claude.com/docs/en/sub-agents). Restart Claude Code now (or
    open a new session) and run:
        bash tests/canary-verifier-agent-discovery-part2.sh
    ```

    Exit 0 after the print. Script 1 does NOT dispatch.

  - **Script 2 — `tests/canary-verifier-agent-discovery-part2.sh`:** dispatches via the `Agent` tool with `subagent_type: "canary-readonly"` and a prompt that asks the canary to call `Bash` (running `echo hi`). Asserts the dispatch returns without the agent having executed Bash — either the agent reports the tool is unavailable, or the response contains no Bash-tool output. Robust signal: grep the agent's response for the literal token the Bash command would have emitted (`hi`); MUST be absent. Asserts PASS / FAIL accordingly. Cleans up `.claude/agents/canary-readonly.md` on success.

  - **Canary header (verbatim, in BOTH script files):** "This canary is auto-discovered at session start; it cannot run within a single CI process. Phase 1.1's gate is the manual two-step run by a developer at plan-execution time. CI registration in `tests/run-all.sh` invokes Script 1 only (which exits 0 cleanly after printing instructions); Script 2 is a developer-driven follow-up."

  - **If Script 2 passes, the structural-allowlist claim is verified.** If it fails, **STOP** the plan — the entire structural design rests on this primitive. Do NOT proceed to authoring the verifier file. Surface the finding to the user.

  - **The `--agents` inline-JSON CLI flag is NOT used as a canary primitive.** Its inline-JSON shape may not accept `tools:` / `hooks:` frontmatter (verify schema against `code.claude.com/docs/en/sub-agents` before any future use), and the spec for this canary is built on the documented `.claude/agents/` discovery path that consumers actually deploy. Keeping the canary on the consumer-deployment path means a passing canary attests to what consumers experience.

- [ ] 1.2 — **Author `.claude/agents/verifier.md`** with the following exact frontmatter and body shape:

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
            command: "bash $CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash-no-background.sh"
  ---

  # Verifier subagent

  You are a verifier subagent. Your job: read the diff, run tests, check acceptance criteria, fix verifiable issues, commit on pass.

  **You cannot run Bash with `run_in_background: true`.** A frontmatter PreToolUse hook rejects it. Always foreground-Bash with `timeout: 600000` (10 minutes) and capture to file:

  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "<worktree-path>")"
  mkdir -p "$TEST_OUT"
  $FULL_TEST_CMD > "$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}" 2>&1
  ```

  Read the file when the call returns.

  **You cannot dispatch sub-subagents.** Subagents categorically lack the `Agent` tool (per Anthropic's documented design at https://code.claude.com/docs/en/sub-agents). If your task requires fresh-agent fanout, that's the orchestrator's job — do the work inline and report the freshness mode in your verification output.
  ```

  **Justification of allowlist contents:**
  - `Read, Grep, Glob` — read diffs, plan text, test files, source files for AC checks.
  - `Bash` — run tests, run git (read+write: diff, log, show, status, commit), run helper scripts.
  - `Edit, Write` — small fixes (e.g., bumping `metadata.version`, adjusting frontmatter, writing tracking markers, writing reports).
  - **Excluded:** `Monitor`, `BashOutput` (close the anti-pattern channel structurally). `Agent` (subagents categorically can't dispatch — including it would not help and would surface a confusing error). `WebFetch`, `WebSearch` (verifier should not depend on the network for verification correctness). `Skill` (the verifier runs `/verify-changes` inline as documented; loading more skills mid-verification adds context that defeats fresh-eyes).

  **Justification of `model: inherit`:** matches CLAUDE.md "default OMIT model — inherit parent" rule (`feedback_no_haiku.md`); explicit-`inherit` is doc-stronger than `omit` for an agent file that downstream consumers will read. **MUST NOT** be `haiku`.

  **Trade-offs considered:**
  - `model: opus` explicit. Rejected. Pins model when parent may be Sonnet for legitimate reasons; `inherit` honors caller's choice.
  - Allowlist `Skill`. Rejected. The verifier's task is bounded; it does not need to load arbitrary skills.
  - Allowlist `Agent`. Rejected. Subagents can't dispatch; including it would either silently ignore or produce a confusing tool listing.

- [ ] 1.3 — **Decide `/commit` shape: separate `commit-reviewer.md` agent.** Author `.claude/agents/commit-reviewer.md` as a separate, **read-only** agent definition. Verbatim frontmatter and body:

  ```yaml
  ---
  name: commit-reviewer
  description: Read-only review of staged diff before /commit finalizes. Dispatched explicitly by /commit Phase 5 step 3 — never auto-invoked. FORBIDDEN to run any state-mutating git command or file edit.
  tools: Read, Grep, Glob, Bash
  model: inherit
  hooks:
    PreToolUse:
      - matcher: "Bash"
        hooks:
          - type: command
            command: "bash $CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash-no-background.sh"
          - type: command
            command: "bash $CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash-readonly.sh"
  ---

  # commit-reviewer subagent

  You are a read-only reviewer. Your job: review `git diff --cached` and the proposed commit message, report concerns or approve. You cannot edit files, stage, unstage, stash, checkout, restore, reset, add, rm, or commit.

  Allowed Bash: `git diff`, `git log`, `git show`, `git show-ref`, `git ls-files`, `git ls-remote`, `git status` (and any read-only helper script). All other git verbs are blocked by the readonly-bash hook. Past failure: a reviewer ran `git stash -u && test && git stash pop`; the pop silently unstaged the caller's staged files.
  ```

  **Why separate (not shared with `verifier.md`):** the read-only constraint is structural, not advisory. /commit's reviewer must NEVER `git stash` or edit files (the past-failure `git stash -u && pop` incident is the reason). Forcing this through a shared `verifier.md` would either weaken `verifier.md` (drop `Edit`/`Write`/state-mutating Bash) or rely on prose discipline within the dispatch prompt. Two definitions with explicit, mechanically-enforced surfaces is cleaner. The marginal cost (one more agent file) is worth it: each definition's purpose is unambiguous from its frontmatter alone.

  **Trade-offs considered:**
  - **Shared `verifier.md` with read-only prose preamble in /commit's dispatch.** Rejected. Read-only-by-prose is exactly the discipline that PR #148's Monitor warning failed to enforce — proven insufficient for safety-critical constraints.
  - **Shared `verifier.md` with a runtime `--readonly` parameter.** Rejected. Claude Code agent definitions don't support invocation-time parameters that flip frontmatter (verified: `code.claude.com/docs/en/sub-agents` schema lists no such field).

- [ ] 1.4 — **Author `hooks/validate-bash-no-background.sh`** (zskills repo source — sister of existing `hooks/block-unsafe-generic.sh`, `hooks/block-agents.sh`, `hooks/warn-config-drift.sh`). Mirrors at install time to `.claude/hooks/validate-bash-no-background.sh` (the installed convention zskills already uses for hooks; verified by `ls /workspaces/zskills/.claude/hooks/` showing `block-*.sh` siblings). The script is a `PreToolUse` hook that reads JSON `tool_input` from stdin and rejects any input where `run_in_background` is `true`. **Bash regex only — no `jq`.**

  **Decision (C4 — fixed, not punted):** use a **key-boundary-anchored** regex so JSON content-only matches (e.g., `echo` of a string containing the literal `run_in_background":true` substring) ALLOW. The leading character class `[{,]` ensures we match only at object-key positions — JSON keys are preceded by either the object opener `{` or the inter-key separator `,`. Skeleton:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail

  INPUT="$(cat)"

  # Match "run_in_background": true ONLY at JSON object-key positions.
  # The leading [{,] requires the key be at top level OR after a sibling key.
  # Whitespace-tolerant. Case-sensitive 'true' (per JSON spec).
  if [[ "$INPUT" =~ [\{,][[:space:]]*\"run_in_background\"[[:space:]]*:[[:space:]]*true([[:space:]]|,|\}) ]]; then
    cat <<'JSON'
  {
    "decision": "block",
    "reason": "Bash(run_in_background: true) is forbidden in this subagent. Wake events for background processes do not reliably deliver to one-shot subagent dispatches; foreground-Bash with explicit timeout: 600000 and capture output to a file. See skills/verify-changes/SKILL.md and CLAUDE.md (verifier-cannot-run rule)."
  }
  JSON
    exit 0
  fi

  # Default: allow (emit no decision).
  exit 0
  ```

  **Test fixture:** add `tests/test-validate-bash-no-background.sh` (registered in `tests/run-all.sh`) with these cases (each asserts a precise outcome — no "acceptable false-positive" cases):
  - Case 1: Input `{"command":"npm test","run_in_background":true}` → exit 0, stdout contains `"decision": "block"`.
  - Case 2: Input `{"command":"npm test","run_in_background":false}` → exit 0, stdout empty.
  - Case 3: Input `{"command":"npm test"}` (no field) → exit 0, stdout empty.
  - Case 4 (the strict-regex check): Input `{"command":"echo \"run_in_background\\\":true is in a string\""}` (literal substring inside a quoted command-string value, NOT as a top-level key) → exit 0, stdout empty (**ALLOW**). The leading `[{,]` boundary in the regex prevents this content-only match from triggering the block. This case is the regress test for C4's resolution.
  - Case 5: Input `{"command":"npm test", "run_in_background" : true }` (whitespace variants) → exit 0, stdout contains `"decision": "block"`.
  - Case 6: Input `{"command":"npm test","run_in_background":true,"description":"runs tests"}` (key followed by another key) → exit 0, stdout contains `"decision": "block"` — verifies the trailing `([[:space:]]|,|\})` boundary class. (N10 fix — round-1 case 6 used a `\\n` literal that is NOT a real newline; the case duplicated case 7's trailing-boundary coverage. Dropped; renumbered.)

- [ ] 1.5 — **Author `hooks/validate-bash-readonly.sh`** (sister hook for `commit-reviewer`; same source-location convention as 1.4). Rejects state-mutating Bash commands. Bash regex only:

  ```bash
  #!/usr/bin/env bash
  set -euo pipefail
  INPUT="$(cat)"
  # Extract command field. Tolerant of escaped quotes inside the value.
  if [[ "$INPUT" =~ \"command\"[[:space:]]*:[[:space:]]*\"((\\\"|[^\"])*)\" ]]; then
    CMD="${BASH_REMATCH[1]}"
  else
    exit 0
  fi
  # Forbidden git verbs (state-mutating). Word-boundary match.
  if [[ "$CMD" =~ git[[:space:]]+(stash|checkout|restore|reset|add|rm|commit|push|merge|rebase|cherry-pick|revert|tag|branch[[:space:]]+-D) ]]; then
    cat <<'JSON'
  { "decision": "block", "reason": "commit-reviewer is read-only. Forbidden: git stash/checkout/restore/reset/add/rm/commit/push/merge/rebase/cherry-pick/revert/tag/branch -D. Use git show <commit>:<file> for pre-fix state." }
  JSON
    exit 0
  fi
  # Forbidden general verbs — word-boundary form catches the verb ANYWHERE in the
  # command (not just top-level). N6 fix: env-var prefix (`FOO=bar rm /etc/x`),
  # &&-chained commands (`git diff && rm foo`), subshells (`(rm foo)`), and pipe
  # tails (`echo x | rm foo`) all bypass a `^[[:space:]]*` anchor.
  # The leading `(^|[^a-zA-Z_])` requires the verb begin at the string start OR
  # be preceded by a non-identifier character (space, `&`, `;`, `(`, `|`, etc.),
  # so `npm test` (verb `test` not in our set, but illustrative) is unaffected
  # and `mvbacon` (literal substring 'mv' inside an identifier) is NOT matched.
  if [[ "$CMD" =~ (^|[^a-zA-Z_])(rm|mv|cp|tee|chmod|chown|dd|truncate)([[:space:]]|$|\;|\&|\|) ]]; then
    cat <<'JSON'
  { "decision": "block", "reason": "commit-reviewer is read-only. Forbidden: rm, mv, cp, tee, chmod, chown, dd, truncate (anywhere in the command, including after env-var prefix, &&, ;, |, or in subshells). The reviewer cannot edit reality." }
  JSON
    exit 0
  fi
  exit 0
  ```

  **Test fixture:** `tests/test-validate-bash-readonly.sh` with adversarial cases per N6:
  - `FOO=bar rm /etc/x` → BLOCK (env-var prefix bypass)
  - `git diff && rm foo` → BLOCK (&&-chain bypass)
  - `(rm foo)` → BLOCK (subshell bypass)
  - `echo x | rm foo` → BLOCK (pipe-tail bypass)
  - `rm foo` → BLOCK (top-level — baseline)
  - `npm test` → ALLOW (verb `test` not in forbidden set)
  - `bash tests/run-all.sh` → ALLOW (verb `bash` not in forbidden set)
  - `git diff && grep foo` → ALLOW (no forbidden verb anywhere)
  - `git diff` → ALLOW (read-only git)
  - `mvbacon foo` → ALLOW (literal substring `mv` inside identifier `mvbacon`; `[^a-zA-Z_]` boundary blocks the match)

  **Note on test-runner ALLOW cases:** test-runner invocations (`npm test`, `bash tests/run-all.sh`, `bash scripts/test-all.sh`, etc.) pass the readonly hook because the regex matches only verbs in the FORBIDDEN SET — `npm`, `bash`, `git diff`, `grep`, `cmp`, `awk`, etc. are not state-mutating Bash verbs (in this hook's enforcement scope), and the regex does not introspect what those subprocesses ultimately do. The reviewer DOES need to run the test suite. The N6 strengthening catches the forbidden verbs themselves wherever they appear, including chained / subshelled / env-prefixed forms; it does NOT introspect subprocess behavior — that is intentional and out of scope for a syntactic Bash-tool hook.

- [ ] 1.6 — **Pick the failure-protocol detection signal.** Decision: **stalled-string match on the verifier's returned response text**, with a strict whitelist of trigger phrases. Rationale: of the four candidates (stalled-string, missing test summary, agent-timeout-exceeded, `stop_reason`), only stalled-string + agent-timeout are reliably exposed to the orchestrator at dispatch-return time. `stop_reason` is documented-not-exposed in current Claude Code (research finding); missing-test-summary requires the orchestrator to parse free-form prose and false-positives on legitimately-skipped phases. Stalled-string match on a tight whitelist plus the existing 45-min agent timeout (already in `/run-plan` Phase 3:1275-1280) gives two robust signals.

  **Whitelist (case-insensitive substring match — applied ONLY to the LAST 5 LINES of the verifier's final response, NOT to anywhere in the response):**
  - `let me wait for the monitor` (the canonical PR #175 failure phrase)
  - `tests are running. let me wait` (variant)
  - `monitor will signal` / `monitor to signal` (Codex-equivalent phrase from Anthropic GH #50572)
  - `still searching. let me wait` (Codex-equivalent)
  - `waiting on bashoutput` (behavioral phrase — verifier explicitly polling)
  - `polling bashoutput` (behavioral phrase — verifier explicitly polling)

  **C2 fix — `bashoutput` bare-substring removed.** A bare `bashoutput` substring would false-positive on legitimate verifier prose like "Note: BashOutput tool not in my allowlist" or "verifier excluded BashOutput per spec." The behavioral phrases `waiting on bashoutput` / `polling bashoutput` capture the actual anti-pattern (the verifier ended its turn while *waiting* on a backgrounded poll). The other 5 phrases independently capture the failure mode without naming any tool.

  **Last-N-lines anchoring rationale.** The failure mode is the verifier ending its turn with one of these phrases — i.e., the phrase is in the trailing message, not buried in earlier prose where the verifier might be quoting the warning text from PR #148's SKILL.md or this plan. Anchoring to `tail -n 5` of `$VERIFIER_RESPONSE` eliminates contamination from the verifier reading and quoting documentation that contains the trigger phrases. Implementation: `LAST5=$(printf '%s' "$VERIFIER_RESPONSE" | tail -n 5 | tr '[:upper:]' '[:lower:]')` then substring-match against `$LAST5`.

  **Trigger condition:** ANY whitelist phrase appears in the LAST 5 LINES of the verifier's final response text (the string returned from the `Agent` tool dispatch). Detection runs in the orchestrator immediately after dispatch returns.

  **STOP message (verbatim, emitted by `/run-plan` to the user):**
  ```
  STOP: verifier returned without running tests.

  The verification subagent's response contains a stalled-string pattern
  ("<matched phrase>"), indicating it hit the run_in_background+Monitor anti-
  pattern and ended its turn without test results. This is a verification
  FAIL, not a routing decision.

  Failure Protocol:
  1. Roll back any uncommitted phase work in <worktree-path>
     (git status; user-driven cleanup).
  2. Tracker entry: requires.verify-changes.<TRACKING_ID> stays unfulfilled.
  3. If you just installed the verifier agent (this is the first
     dispatch of the session post-install), restart Claude Code (or
     open a new session) before re-dispatching — `.claude/agents/`
     is auto-discovered ONLY at session start (per
     code.claude.com/docs/en/sub-agents priority table). There is
     no in-session reload command; `/agents reload` does not exist.
  4. Halt the pipeline. Do not auto-retry. Re-dispatch only after
     surfacing the failure and confirming the verifier agent file is
     installed (.claude/agents/verifier.md exists; bash $CLAUDE_PROJECT_DIR/
     .claude/hooks/validate-bash-no-background.sh < /dev/null exits 0).
  ```

  **No automatic re-dispatch.** Re-dispatching with the same agent type would hit the same wall. Recovery requires either (a) the verifier agent file being missing/broken (install path failure — Phase 5 closes that hole), or (b) Anthropic-side wake-event behavior changing (out of scope). User-driven recovery only.

  **Trade-offs considered:**
  - `stop_reason` extraction. Rejected — not reliably exposed to orchestrator prompt context per docs research. Specing against an unverified primitive risks the same class of bug we're closing.
  - Missing-test-summary parse. Rejected — false-positives on legitimately-skipped phases (`Tests: skipped — no test infra`) and on content-only `/do` paths.
  - Agent-timeout-exceeded only (no stalled-string). Rejected — 45-min timeout is the upper bound; PR #175 verifiers hung for the full 45 minutes wasting agent time. Stalled-string detection catches the failure mode within ~30 seconds of dispatch return.
  - Stalled-string AND `stop_reason`. Rejected — adding an unverified signal as a co-trigger risks false-negatives without adding robustness.

- [ ] 1.7 — **Append a `## Verifier-cannot-run rule` section to `CLAUDE.md`.** Single paragraph, verbatim:

  > **Verifier-cannot-run is a verification FAIL, not a routing decision.** When a dispatched verification subagent returns without running tests — whether because it hit the `run_in_background: true` + `Monitor`/`BashOutput` anti-pattern, exceeded the 45-minute agent timeout, or returned an empty/no-results response matching one of the stalled-string trigger phrases — the orchestrator MUST invoke the Failure Protocol (STOP, halt the pipeline, surface to the user) instead of logging a one-line note and proceeding. Inline self-verification by the orchestrator is NOT acceptable recovery — the orchestrator wrote the impl prompts and has implementer bias. The structural defense lives in `.claude/agents/verifier.md` (frontmatter `tools:` allowlist excluding `Monitor`/`BashOutput`) and `.claude/hooks/validate-bash-no-background.sh` (frontmatter `PreToolUse` hook rejecting `run_in_background: true`); both must be installed and functional. Past failures: PR #175 (skill-versioning, 2026-05-02) — every Phase 1-6 verifier dispatch hit the Monitor pattern; orchestrator did inline verification across 5 of 7 phases and committed unverified work. Issues #176, #180.

### Design & Constraints

- **Tool restriction is structural, not advisory.** Phase 1.1 canary verifies this against current Claude Code. If it fails, halt the plan.
- **`PreToolUse` hook is required AND structural.** Allowlist alone leaves `Bash(run_in_background: true)` callable. Hook closes that hole.
- **`commit-reviewer` is a separate agent definition**, not a parameterized verifier. Read-only is structural.
- **`model: inherit` only.** Never `haiku`. Per CLAUDE.md.
- **Bash regex (`BASH_REMATCH`) for hook scripts.** No `jq`. No exceptions.
- **No skill `metadata.version` bumps in this phase.** Phase 1 lands `.claude/agents/`, `hooks/`, `tests/`, `CLAUDE.md` only. The 5 skill bumps land in Phases 2 and 3.
- **`.claude/agents/` is greenfield.** No prior files; create the directory in this commit. Verified `ls /workspaces/zskills/.claude/agents/` returns `No such file or directory` at plan-draft time.
- **Hook script install path (verified, NOT invented).** Source lives at `hooks/validate-bash-no-background.sh` and `hooks/validate-bash-readonly.sh`. Install path is `.claude/hooks/<name>.sh` — sister of existing `.claude/hooks/block-unsafe-generic.sh`, `.claude/hooks/block-agents.sh`, `.claude/hooks/warn-config-drift.sh`. Verified by `ls /workspaces/zskills/.claude/hooks/` listing those four siblings; `ls /workspaces/zskills/.claude/scripts/` returns ENOENT — `.claude/scripts/` does NOT exist in zskills and is NOT introduced by this plan. Agent frontmatter references `$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh`.
- **Mirror the agent files into `.claude/agents/`** at the end of Phase 1 commit (zskills uses source `skills/` + mirrored `.claude/skills/` for agent-tool consumption; same convention applies to `.claude/agents/` and `.claude/hooks/`).
- **#176 reporter's "Option 1" rejected — justification (kept inline, no separate references doc per R4):** structural-allowlist + PreToolUse hook beats orchestrator-runs-tests-passes-output-file because (a) **portability** — applies uniformly across all 5 dispatch sites without per-skill changes to test-execution flow; orchestrator-runs-tests would require 5 distinct restructurings (each skill's "run tests; pass output to verifier" flow has different shape — `/run-plan` runs in worktree, `/commit` runs against staged, `/fix-issues` runs per-issue-worktree, `/do` runs against current cwd, `/verify-changes` is the canonical verifier); (b) **closure** — structural defense closes the anti-pattern channel for ALL future verifier work; orchestrator-runs-tests fixes only test-runtime invocations and leaves `Monitor` available for any other long-running tool a future verifier might background (e.g., playwright-cli); (c) **defense-in-depth** — structural composes with PR #148's prose warnings (kept as belt-and-suspenders) and with future orchestrator-runs-tests if that lands separately.
- **Commit boundary (Phase 1):** single commit. Files: `.claude/agents/verifier.md`, `.claude/agents/commit-reviewer.md`, `hooks/validate-bash-no-background.sh`, `hooks/validate-bash-readonly.sh`, `.claude/hooks/validate-bash-no-background.sh` (mirror), `.claude/hooks/validate-bash-readonly.sh` (mirror), `tests/canary-verifier-agent-discovery-part1.sh`, `tests/canary-verifier-agent-discovery-part2.sh`, `tests/test-validate-bash-no-background.sh`, `tests/test-validate-bash-readonly.sh`, `tests/run-all.sh` (3 new `run_suite` lines — registers part1 and the two test-validate scripts; part2 is a developer-driven follow-up not registered in CI), `tests/fixtures/canary-agents/canary-readonly.md`, `CLAUDE.md` (Verifier-cannot-run rule). NO source skill `SKILL.md` edits in this commit; NO `metadata.version` bumps in this commit.

### Acceptance Criteria

- [ ] AC-1.1 — `bash tests/canary-verifier-agent-discovery-part1.sh` exits 0 and prints the verbatim restart instruction to stdout. After a manual session-restart by a developer at plan-execution time, `bash tests/canary-verifier-agent-discovery-part2.sh` exits 0 with at least 1 PASS line AND the canary response text does NOT contain the literal token `hi` that would have been emitted by Bash. The two-script flow is the canonical canary path; part2 is a developer-driven follow-up (NOT registered in CI's `tests/run-all.sh` since it cannot run in a single CI process — see canary header).
- [ ] AC-1.2 — `[ -f /workspaces/zskills/.claude/agents/verifier.md ] && [ -f /workspaces/zskills/.claude/agents/commit-reviewer.md ]` — both files exist.
- [ ] AC-1.3 — `awk '/^---$/{f=!f;next} f && /^tools:/' /workspaces/zskills/.claude/agents/verifier.md` returns a single line containing `Read, Grep, Glob, Bash, Edit, Write` (and NOT `Monitor`, `BashOutput`, `Agent`, `WebFetch`, `WebSearch`, `Skill`).
- [ ] AC-1.4 — `awk '/^---$/{f=!f;next} f && /^model:/' /workspaces/zskills/.claude/agents/verifier.md` returns `model: inherit`. The string `haiku` MUST NOT appear in the file: `! grep -q 'haiku' /workspaces/zskills/.claude/agents/verifier.md`.
- [ ] AC-1.5 — `[ -x /workspaces/zskills/hooks/validate-bash-no-background.sh ] && [ -x /workspaces/zskills/.claude/hooks/validate-bash-no-background.sh ]` AND `bash tests/test-validate-bash-no-background.sh` exits 0 with **all 6 cases** asserting precise per-case outcomes: cases 1, 5, 6 → block; cases 2, 3, 4 → allow (empty stdout). Case 4 specifically asserts the content-only `echo "...run_in_background\":true..."` is **ALLOWED** (regress test for the C4 strict-regex resolution). Case 6 verifies the trailing-boundary class `([[:space:]]|,|\})` against a `,"description":...` follow-up key. (N10 — round-1 had 7 cases; case 6 used `\\n` literal that isn't a real newline and duplicated case 7's coverage; dropped, renumbered.)
- [ ] AC-1.6 — `[ -x /workspaces/zskills/hooks/validate-bash-readonly.sh ] && [ -x /workspaces/zskills/.claude/hooks/validate-bash-readonly.sh ]` AND `bash tests/test-validate-bash-readonly.sh` exits 0 with all cases PASS. Adversarial-bypass BLOCK assertions (N6 fix): `FOO=bar rm /etc/x`, `git diff && rm foo`, `(rm foo)`, `echo x | rm foo`, `rm foo`. ALLOW assertions: `npm test`, `bash tests/run-all.sh`, `bash scripts/test-all.sh`, `git diff && grep foo`, `git diff`, `mvbacon foo` (identifier-boundary regress).
- [ ] AC-1.7 — `grep -F 'Verifier-cannot-run is a verification FAIL' /workspaces/zskills/CLAUDE.md` returns 1+ line.
- [ ] AC-1.8 — `grep -F 'stalled-string trigger phrases' /workspaces/zskills/CLAUDE.md` returns 1+ line (the rule cites the detection signal explicitly).
- [ ] AC-1.9 — `tests/run-all.sh` registers the 3 new test scripts: `grep -F 'canary-verifier-agent-discovery-part1' tests/run-all.sh && grep -F 'test-validate-bash-no-background' tests/run-all.sh && grep -F 'test-validate-bash-readonly' tests/run-all.sh`. Part2 is intentionally NOT registered (cannot run in single CI process).
- [ ] AC-1.10 — Full test suite (resolve `$FULL_TEST_CMD` from config) passes against the captured baseline; new failures are zero. Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt` per CLAUDE.md.

### Dependencies

- None. This phase is self-contained.

---

## Phase 2 — Migrate `/run-plan` Phase 3 + add failure-protocol clause

### Goal

Update `/run-plan` SKILL.md Phase 3 dispatch to pass `subagent_type: "verifier"` to the `Agent` tool, AND add the failure-protocol clause that detects verifier-empty/stalled returns. Bump `skills/run-plan/SKILL.md` `metadata.version`. Mirror via `scripts/mirror-skill.sh`.

### Work Items

- [ ] 2.1 — **Edit `skills/run-plan/SKILL.md` Phase 3 dispatch protocol** (`### Worktree mode verification` section, currently lines ~1355-1454). At each `Agent`-tool dispatch site (worktree mode + delegate mode), add an explicit `subagent_type: "verifier"` parameter. Today the dispatch is described as "dispatch verification agent targeting the worktree's changes" without an explicit subagent_type — the migration is to MAKE the parameter explicit, not to flip an existing value.

  Insert a verbatim instruction block just above the dispatch description:

  > **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The verifier agent definition lives at `.claude/agents/verifier.md` and is structurally restricted: tools allowlist excludes `Monitor`/`BashOutput`, frontmatter `PreToolUse` hook rejects `Bash(run_in_background: true)`. The verifier CANNOT dispatch sub-subagents — fix-agent dispatch (Phase 3 step 3 "fresh fix agent") stays at the orchestrator level. If the dispatch returns "no such agent" or equivalent, the verifier agent file is missing — STOP and run `/update-zskills` (which Phase 5 of the verifier-agent-fix plan teaches to install `.claude/agents/verifier.md`).

- [ ] 2.2 — **Add the failure-protocol clause to Phase 3.** Insert as a new subsection `### Failure Protocol — verifier-empty/stalled detection` immediately AFTER the `### Worktree mode verification` numbered list (between current numbered item 3 and `#### Plan-text drift signals (worktree mode verification)`). Body verbatim:

  > **Failure Protocol — verifier-empty/stalled detection.**
  >
  > **Detection runs immediately after the verifier `Agent` dispatch returns**, before any tracker write or commit. Inspect the verifier's final response text (`$VERIFIER_RESPONSE`):
  >
  > ```bash
  > # Stalled-string whitelist (case-insensitive substring match,
  > # anchored to the LAST 5 LINES of the response — NOT anywhere).
  > # The last-5-lines anchor prevents contamination from the verifier
  > # quoting PR #148's warning prose or this plan's own text.
  > STALLED_PATTERNS=(
  >   "let me wait for the monitor"
  >   "tests are running. let me wait"
  >   "monitor will signal"
  >   "monitor to signal"
  >   "still searching. let me wait"
  >   "waiting on bashoutput"
  >   "polling bashoutput"
  > )
  > # Also empty / suspiciously-short response is a fail (D3).
  > MIN_RESPONSE_BYTES=200
  > FAILED=0
  > MATCHED=""
  > if [ ${#VERIFIER_RESPONSE} -lt $MIN_RESPONSE_BYTES ]; then
  >   FAILED=1
  >   MATCHED="(response shorter than $MIN_RESPONSE_BYTES bytes — empty or stub)"
  > else
  >   LAST5=$(printf '%s' "$VERIFIER_RESPONSE" | tail -n 5 | tr '[:upper:]' '[:lower:]')
  >   for pat in "${STALLED_PATTERNS[@]}"; do
  >     if [[ "$LAST5" == *"$pat"* ]]; then
  >       FAILED=1
  >       MATCHED="$pat"
  >       break
  >     fi
  >   done
  > fi
  > ```
  >
  > **Bare `bashoutput` substring is NOT a trigger** (C2 fix). It would false-positive on legitimate verifier prose mentioning the BashOutput tool by name (e.g., "Note: BashOutput tool not in my allowlist"). The behavioral phrases `waiting on bashoutput` / `polling bashoutput` capture the actual anti-pattern.
  >
  > **Minimum-length signal (D3 fix — closes #180's empty-response hole).** A real verification report — even one that legitimately reports "tests skipped — no test infra for this phase" — is at minimum a sentence or two of explanation, well over 200 bytes. A response shorter than 200 bytes is either empty (the agent ended its turn before producing meaningful output) or a stub that does not constitute attestation. Both fail the verifier-cannot-run rule.
  >
  > **AND** detect agent-timeout-exceeded: if the dispatch took longer than 45 minutes (existing rule, line ~1275-1280), treat as failed.
  >
  > **On detection (FAILED=1 OR timeout):** STOP. Do NOT write the verification step marker. Do NOT proceed to Phase 3.5 plan-drift correction. Do NOT proceed to Phase 4 commit. Emit the verbatim STOP message:
  >
  > ```
  > STOP: verifier returned without running tests.
  >
  > The verification subagent's response contains a stalled-string pattern
  > ("$MATCHED"), indicating it hit the run_in_background+Monitor anti-
  > pattern and ended its turn without test results. This is a verification
  > FAIL, not a routing decision.
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
  >    $CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash-no-background.sh
  >    < /dev/null exits 0).
  > ```
  >
  > **Inline self-verification is NOT acceptable recovery.** Per CLAUDE.md ## Verifier-cannot-run rule, the orchestrator MUST NOT inline-verify on this failure path — the orchestrator wrote the implementer prompts and has implementer bias. Wait for user input.
  >
  > **No automatic re-dispatch.** Re-dispatching with the same agent type hits the same wall. Recovery requires either (a) the verifier agent file is missing/broken (Phase 5 of verifier-agent-fix closes that hole) or (b) Anthropic-side wake-event behavior changes (out of scope).

- [ ] 2.3 — **Insert the dispatcher-attribution clarifier (mandatory edit, NOT conditional on prose ambiguity).** Read the "fresh fix agent" branch (Phase 3 step 3, lines ~1441-1454). At the top of the fix-agent dispatch block, insert the following verbatim sentence (find the exact insertion point in the implementation by scanning for the existing "fresh fix agent" / "auto" prose):

  > **Dispatcher: the orchestrator (top-level `/run-plan`), not the verifier subagent.** The verifier's tool allowlist excludes `Agent`; sub-subagent dispatch is categorically unavailable per https://code.claude.com/docs/en/sub-agents. The verifier reports failed-AC findings back; the orchestrator dispatches the fresh fix agent.

  This is mandatory regardless of whether the existing prose is ambiguous — explicitness is structural defense against future prose drift. Add an AC asserting the literal phrase appears in the SKILL.md.

- [ ] 2.4 — **Bump `skills/run-plan/SKILL.md` `metadata.version`.** Recompute via `bash scripts/skill-content-hash.sh skills/run-plan` and replace the value with `YYYY.MM.DD+HHHHHH` per the SKILL_VERSIONING enforcement chain. Both halves change: date (`TZ=America/New_York date +%Y.%m.%d`) AND hash (recomputed from the new content). Verify via `bash scripts/skill-version-stage-check.sh` — must exit 0.

- [ ] 2.5 — **Mirror `skills/run-plan/` to `.claude/skills/run-plan/`** via `bash scripts/mirror-skill.sh run-plan`. Verify byte-equivalence via `diff -rq skills/run-plan/ .claude/skills/run-plan/` (excluding any allow-listed differences from `mirror-skill.sh`).

### Design & Constraints

- **`subagent_type: "verifier"` is added at every `Agent`-tool dispatch in Phase 3** (worktree mode AND delegate mode). The `Agent` tool's `subagent_type` parameter selects the agent definition; without it, Claude Code falls back to `general-purpose` (which lacks the structural restrictions).
- **The failure-protocol clause runs in the orchestrator** (where the dispatch returns), NOT in the verifier (the verifier already failed). The orchestrator inspects `$VERIFIER_RESPONSE` and STOPs.
- **The 45-min agent timeout rule (existing line ~1275-1280) is preserved** as a co-trigger of the failure protocol.
- **PR #148 prose warnings stay** — defense-in-depth. The verifier agent file is the structural primary; prose is documentation.
- **`metadata.version` bump is mandatory** per SKILL_VERSIONING enforcement (PR #175). `/commit` Phase 5 step 2.5 will block the commit otherwise.
- **No edits to `Phase 3.5 plan-text drift` section** — the failure-protocol clause is inserted BEFORE Phase 3.5 takes effect.
- **Single PR, ordered commits — no mid-plan merge.** Phase 2's commit references `subagent_type: "verifier"` against the agent file landed in Phase 1's commit. Both commits ship in the same PR; `main` never sees Phase 2 without Phase 1. This precludes a class of "no such agent" failures on `main` between phases.
- **Commit boundary (Phase 2):** single commit. Files: `skills/run-plan/SKILL.md` (dispatch shape + Failure Protocol section + dispatcher-attribution clarifier + `metadata.version` bump), `.claude/skills/run-plan/SKILL.md` (mirror).

### Acceptance Criteria

- [ ] AC-2.1 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/run-plan/SKILL.md` returns ≥ 2 (worktree-mode dispatch + delegate-mode dispatch).
- [ ] AC-2.2 — `grep -F 'Failure Protocol — verifier-empty/stalled detection' skills/run-plan/SKILL.md` returns 1 line.
- [ ] AC-2.3 — `grep -F 'STOP: verifier returned without running tests' skills/run-plan/SKILL.md` returns 1+ line (the verbatim STOP message body).
- [ ] AC-2.4 — All 7 stalled-string whitelist phrases appear **inside the new Failure Protocol section** (NOT just anywhere in SKILL.md — anchored to prevent matching PR #148 prose at lines 1051-1062 which already contains "Tests are running. Let me wait for the monitor."). Verify with `awk` range-extraction:
  ```bash
  SECTION=$(awk '/^### Failure Protocol — verifier-empty\/stalled detection/,/^### |^---/' skills/run-plan/SKILL.md)
  for p in "let me wait for the monitor" "tests are running. let me wait" "monitor will signal" "monitor to signal" "still searching. let me wait" "waiting on bashoutput" "polling bashoutput"; do
    printf '%s' "$SECTION" | grep -qF "$p" || { echo "missing in Failure Protocol section: $p"; exit 1; }
  done
  ```
  Honest current-state (N5 fix): the phrase "Tests are running. Let me wait for the monitor." is currently split across a markdown line break at `skills/run-plan/SKILL.md:1058-1059`, so a flat-file `grep -F` does NOT match it as one phrase TODAY (verified: `for p in <7 phrases>; do grep -ciF "$p" skills/run-plan/SKILL.md; done` returns all zeros at plan-refinement time). The awk section-anchor is NOT necessary to defeat current PR #148 prose — but it IS defense-in-depth against an unintended whole-file reflow that could collapse the phrase onto a single line and cause flat-grep to false-pass for the phrase even without the new content. Keeping the anchor is zero-cost insurance against future markdown reflows; the C5 round-1 framing of "anchor needed because bare grep currently passes" was empirically false.
- [ ] AC-2.4b — Bare `bashoutput` substring does NOT appear in the Failure Protocol section's STALLED_PATTERNS array (C2 fix): `awk '/^### Failure Protocol — verifier-empty\/stalled detection/,/^### |^---/' skills/run-plan/SKILL.md | awk '/STALLED_PATTERNS=/,/^> \)$|^>  *\)$/' | grep -E '^>[[:space:]]+"bashoutput"$'` returns no output.
- [ ] AC-2.4c — Last-N-lines anchoring is documented in the Failure Protocol section: `awk '/^### Failure Protocol — verifier-empty\/stalled detection/,/^### |^---/' skills/run-plan/SKILL.md | grep -F 'tail -n 5'` returns 1+ line.
- [ ] AC-2.4d — Minimum-length signal is documented in the Failure Protocol section: `awk '/^### Failure Protocol — verifier-empty\/stalled detection/,/^### |^---/' skills/run-plan/SKILL.md | grep -F 'MIN_RESPONSE_BYTES=200'` returns 1+ line.
- [ ] AC-2.4e — Dispatcher-attribution clarifier (D1) is in the SKILL.md verbatim: `grep -F 'Dispatcher: the orchestrator (top-level \`/run-plan\`), not the verifier subagent' skills/run-plan/SKILL.md` returns 1 line.
- [ ] AC-2.5 — `bash scripts/skill-version-stage-check.sh` exits 0 (worktree state's per-skill projection hash matches the staged `metadata.version` line).
- [ ] AC-2.6 — The staged `metadata.version` matches the schematic shape `YYYY.MM.DD+HHHHHH` where date is today (`TZ=America/New_York date +%Y.%m.%d`) and hash is 6 lowercase hex chars: `awk '/^metadata:/{f=1;next} f && /version:/{print; exit}' skills/run-plan/SKILL.md | grep -E '^[[:space:]]*version:[[:space:]]*"[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}"$'` returns 1 line. **Plan text uses only schematic placeholders** (`YYYY.MM.DD+HHHHHH`); concrete date+hash literals are forbidden in plan prose to avoid colliding with #179 forbidden-literals scan.
- [ ] AC-2.7 — `diff -rq skills/run-plan/ .claude/skills/run-plan/` returns no output (mirror is byte-equivalent, modulo any documented `mirror-skill.sh` exclusions).
- [ ] AC-2.8 — Full test suite (resolve `$FULL_TEST_CMD` from config) passes; zero new failures vs. baseline. Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`.

### Dependencies

- Phase 1 must be complete (`.claude/agents/verifier.md` exists and the canary passed). **Both phases ship in the same PR — Phase 2's commit follows Phase 1's commit on the feature branch; neither lands on `main` independently.**

---

## Phase 3 — Migrate `/commit`, `/fix-issues`, `/do`, `/verify-changes`

### Goal

Add explicit `subagent_type:` parameters to the verifier-dispatch sites in the remaining 4 skills. `/commit` uses `subagent_type: "commit-reviewer"` (read-only agent); the other 3 use `subagent_type: "verifier"`. Bump each modified skill's `metadata.version`. Mirror each.

### Work Items

- [ ] 3.1 — **Edit `skills/commit/SKILL.md` Phase 5 step 3** (currently lines ~274-299). At the dispatch site, add explicit `subagent_type: "commit-reviewer"` instruction. Insert a verbatim block above the existing read-only prose:

  > **Dispatch shape.** Use the `Agent` tool with `subagent_type: "commit-reviewer"`. The commit-reviewer agent definition lives at `.claude/agents/commit-reviewer.md` and is structurally restricted: tools allowlist `Read, Grep, Glob, Bash` (no `Edit`, no `Write`); frontmatter `PreToolUse` hooks reject `Bash(run_in_background: true)` AND state-mutating Bash verbs (`git stash/checkout/restore/reset/add/rm/commit/push/merge/rebase/cherry-pick/revert/tag/branch -D`, `rm`, `mv`, `cp`, `tee`, `truncate`, `chmod`, `chown`). The "you are read-only" prose below is preserved as belt-and-suspenders documentation.

  Keep the existing read-only prose verbatim — it's defense-in-depth and downstream documentation for any maintainer reading the dispatch source.

- [ ] 3.2 — **Bump `skills/commit/SKILL.md` `metadata.version`.** Same procedure as Phase 2.4. Verify via `bash scripts/skill-version-stage-check.sh`.

- [ ] 3.3 — **Mirror `skills/commit/`** via `bash scripts/mirror-skill.sh commit`.

- [ ] 3.4 — **Edit `skills/fix-issues/SKILL.md` `### Dispatch protocol` section** (currently lines ~950-980). At the per-issue verification dispatch site (the call to "dispatch a fresh agent to run `/verify-changes worktree`"), add explicit `subagent_type: "verifier"`. Insert a verbatim block above the dispatch:

  > **Dispatch shape.** Use the `Agent` tool with `subagent_type: "verifier"`. The verifier agent definition is at `.claude/agents/verifier.md` (tools allowlist excludes `Monitor`/`BashOutput`; PreToolUse hook rejects `Bash(run_in_background: true)`). Per Anthropic's documented design, the verifier cannot dispatch sub-subagents — for the per-issue case this is fine: each verifier handles one issue's worktree. If a verification reveals a fix is needed, surface to the user (or to `/run-plan` if dispatched by it); the orchestrator dispatches any fix agent.

- [ ] 3.5 — **Bump `skills/fix-issues/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.6 — **Edit `skills/do/SKILL.md` Phase 3 verification dispatches** (currently lines ~708-754). Two distinct shapes — both gain explicit subagent_type:
  - **Code-changes path** (line ~744): "dispatch a separate verification agent running `/verify-changes`" → add `subagent_type: "verifier"`.
  - **Content-only path** (line ~717): "dispatch a separate verification agent. Tell the agent explicitly: 'These are content-only changes (no code). Review the diff for correctness…'" → also use `subagent_type: "verifier"`. Justification: verifier's allowlist (`Read, Grep, Glob, Bash, Edit, Write`) is sufficient for content review (Read + Grep cover the main path); the prose preamble in the dispatch keeps it from running tests. The verifier's PreToolUse-Bash hook does NOT block tests by name — tests are simply not invoked because the prompt says "do NOT run npm test". The structural fix at this site is the Monitor/background-Bash restriction, which applies to content-review agents the same as code-review agents (no scenario where a content-review agent should background a process either).

- [ ] 3.7 — **Bump `skills/do/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.8 — **Edit `skills/verify-changes/SKILL.md` `### Dispatch protocol` section** (currently lines 31-67). The canonical verifier IS itself a dispatcher — it dispatches sub-agents for diff/coverage/manual reviews when it has the `Agent` tool. After this plan lands, `/verify-changes` is most often invoked BY the new `verifier` subagent, which lacks `Agent` — so the inline fallback path (`:43-61`) is the live path. Update the dispatch protocol to note this explicitly and to describe what happens when `/verify-changes` IS invoked at the top level (still has `Agent`):

  > **Dispatch shape (top-level invocation).** When `/verify-changes` is invoked at the top level AND the orchestrator has the `Agent` tool, dispatched sub-agents use `subagent_type: "verifier"`. When invoked from within a `verifier` subagent (the typical case after this plan lands), the `Agent` tool is unavailable categorically — fall through to the inline path (`:43-61`). Document the freshness mode in the verification report ("multi-agent" / "single-context fresh-subagent" / "inline self-review").

  Add the explicit `subagent_type: "verifier"` parameter at the top-level dispatch site(s) within `/verify-changes` itself.

- [ ] 3.9 — **Bump `skills/verify-changes/SKILL.md` `metadata.version`.** Verify, mirror.

- [ ] 3.10 — **Audit:** verify NO skill outside the migration scope ({`commit`, `fix-issues`, `do`, `verify-changes`, `run-plan`}) was modified across the entire feature branch. Use a **branch-range** diff (NOT `HEAD~1`, which only sees the most recent commit and would silently pass even if an earlier commit modified out-of-scope skills): `git diff --name-only main...HEAD -- skills/ | grep -v -E '^skills/(commit|fix-issues|do|verify-changes|run-plan)/'` returns no output. (Phase 2 modified `run-plan`; this phase modifies the other 4.)

### Design & Constraints

- **Bundle all 4 remaining skills in this phase, not staged.** Per `feedback_dont_defer_hole_closure.md`. The structural fix is one design; partial migration leaves 1-3 skills still hitting the Monitor anti-pattern. Coherence > smaller PRs.
- **`/commit` uses `commit-reviewer`, others use `verifier`.** Read-only structural restriction on /commit is non-negotiable per past failure (`git stash -u` reviewer incident).
- **`/do` content-only path uses `verifier` not a third agent type.** The verifier's allowlist suffices; adding a `content-reviewer.md` agent definition would multiply files without adding safety. Prose preamble in the dispatch ("do NOT run tests") suffices for the test-skip discipline.
- **Each modified skill bumps `metadata.version`.** 4 bumps in this phase + 1 in Phase 2 = 5 total skill bumps for the plan.
- **`/verify-changes` modification is to the dispatch protocol prose (line 31-67), not the inline fallback.** The fallback path doesn't dispatch — it runs inline — and needs no agent-type changes.
- **`/verify-changes` freshness-mode reporting is mandatory.** When invoked from inside a `verifier` subagent (the post-plan typical case), `Agent` is unavailable; `/verify-changes` falls through to inline self-review. The verification report MUST explicitly state the freshness mode used (one of: `multi-agent` / `single-context fresh-subagent` / `inline self-review`) so the orchestrator and downstream readers can audit the freshness guarantee. AC-3.10 below asserts this.
- **PR #148 prose warnings (in `/run-plan`, `/do`, `/fix-issues`, `/verify-changes`) stay.** Defense-in-depth.
- **Single PR — Phase 3 commits ship on the same feature branch as Phases 1, 2.** No interim `main` merge.
- **Commit boundary (Phase 3):** four ordered commits — one per migrated skill — each commit pairs the source SKILL.md edit + the `metadata.version` bump + the mirror under `.claude/skills/`. Files per commit:
  - Commit 3-A: `skills/commit/SKILL.md`, `.claude/skills/commit/SKILL.md`.
  - Commit 3-B: `skills/fix-issues/SKILL.md`, `.claude/skills/fix-issues/SKILL.md`.
  - Commit 3-C: `skills/do/SKILL.md`, `.claude/skills/do/SKILL.md`.
  - Commit 3-D: `skills/verify-changes/SKILL.md`, `.claude/skills/verify-changes/SKILL.md`.
  Per-skill commits keep `/commit` Phase 5 step 2.5 happy (each commit's staged set is exactly one skill — single content + single version line bumped).

### Acceptance Criteria

- [ ] AC-3.1 — `grep -c 'subagent_type:[[:space:]]*"commit-reviewer"' skills/commit/SKILL.md` returns ≥ 1.
- [ ] AC-3.2 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/fix-issues/SKILL.md` returns ≥ 1.
- [ ] AC-3.3 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/do/SKILL.md` returns ≥ 2 (code path + content-only path).
- [ ] AC-3.4 — `grep -c 'subagent_type:[[:space:]]*"verifier"' skills/verify-changes/SKILL.md` returns ≥ 1.
- [ ] AC-3.5 — Per-skill `metadata.version` freshness across all 4 staged skills: `bash scripts/skill-version-stage-check.sh` exits 0 against the staged set. (R1 — verified by reading `/workspaces/zskills/scripts/skill-version-stage-check.sh:30-48`: the script reads `git diff --cached --name-only`, builds an internal `SKILLS_TO_CHECK` map, and iterates — it takes NO argv. Per-skill content-hash sanity, if needed, uses `bash scripts/skill-content-hash.sh skills/<name>`.)
- [ ] AC-3.6 — `for s in commit fix-issues do verify-changes; do diff -rq skills/$s/ .claude/skills/$s/ || exit 1; done` returns no output (all 4 mirrors clean).
- [ ] AC-3.7 — Out-of-scope-skills audit uses the branch range, not the last commit (R2): `git diff --name-only main...HEAD -- skills/ | grep -v -E '^skills/(commit|fix-issues|do|verify-changes|run-plan)/'` returns no output.
- [ ] AC-3.8 — Full test suite passes; zero new failures vs. baseline. Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`.
- [ ] AC-3.9 — The PR #148 prose warning still appears in each of the 4 originally-warned skills (`/run-plan`, `/do`, `/fix-issues`, `/verify-changes`): `for s in run-plan do fix-issues verify-changes; do grep -qF 'run_in_background' skills/$s/SKILL.md || { echo "missing in $s"; exit 1; }; done` exits 0. (Belt-and-suspenders preserved.)
- [ ] AC-3.10 — `/verify-changes` SKILL.md documents the freshness-mode-reporting requirement (R3): `grep -F 'multi-agent' skills/verify-changes/SKILL.md && grep -F 'single-context fresh-subagent' skills/verify-changes/SKILL.md && grep -F 'inline self-review' skills/verify-changes/SKILL.md` returns at least one line per phrase. The dispatch-protocol section explicitly instructs the reporter to state which mode was used.

### Dependencies

- Phase 1 must be complete (`.claude/agents/verifier.md` and `.claude/agents/commit-reviewer.md` both exist).
- Phase 2 must be complete (run-plan migration is the model the other 4 follow).

---

## Phase 4 — Canaries: agent discovery, hook block, sub-subagent denial, failure-protocol firing

### Goal

Add 4 canary tests proving the structural fix holds end-to-end. Each canary is a sandbox-based, registered test under `tests/`, runnable via `tests/run-all.sh`.

### Work Items

- [ ] 4.1 — **Canary 1 — Verifier agent discovery + tool restriction structural.** `tests/canary-verifier-tools-allowlist.sh`.

  **Probe step (FIRST — converts silent-pass into loud assertion failure).** At canary start, dispatch a minimal probe: `Agent(subagent_type: "verifier", prompt: "Reply with literal string CANARY-PROBE-OK and nothing else.")`. Assert the response contains the literal token `CANARY-PROBE-OK`. If absent, exit 0 with the verbatim line `agent not yet discovered — fresh session required (.claude/agents/ auto-discovers at session start; restart Claude Code or open a new session, then re-run this canary)` printed to stdout. Loud, not silent — the canary deliberately exits 0 to allow the suite to continue but emits an unmistakable header that a human / CI grep can match. Then proceed to the real assertion.

  **Real assertion (after probe passes).** Dispatch `subagent_type: "verifier"` with a prompt that asks the agent to call `Monitor` or `BashOutput` (e.g., "Call the BashOutput tool on shell `_test`"). Assertion: the agent's response contains a tool-unavailable signal (e.g., the literal word `not available` or `tools allowed:` referencing only the allowlist) AND does NOT contain any `BashOutput` tool result. Expected exit: 0 with PASS.

- [ ] 4.2 — **Canary 2 — `Bash(run_in_background: true)` rejected by hook.** `tests/canary-verifier-bash-no-background.sh`. Two cases:
  - Case A: Run `bash hooks/validate-bash-no-background.sh` directly with input `{"command":"sleep 60","run_in_background":true}` on stdin. Assert exit 0 AND stdout contains `"decision": "block"`.
  - Case B: Run with input `{"command":"sleep 1","run_in_background":false}`. Assert exit 0 AND stdout is empty.

  This canary is faster and more deterministic than dispatching an actual subagent — it tests the hook script itself, which is the structural primitive. The full end-to-end (subagent → hook → block) is implicitly tested by Claude Code's hook chain semantics (verified by Phase 1.1 canary's same primitive).

- [ ] 4.3 — **Canary 3 — Verifier subagent cannot dispatch sub-subagents.** `tests/canary-verifier-no-subdispatch.sh`.

  **Probe step (FIRST — same as 4.1).** Dispatch `Agent(subagent_type: "verifier", prompt: "Reply with literal string CANARY-PROBE-OK and nothing else.")`. Assert the response contains the literal token `CANARY-PROBE-OK`. If absent, exit 0 with the verbatim line `agent not yet discovered — fresh session required (.claude/agents/ auto-discovers at session start; restart Claude Code or open a new session, then re-run this canary)` printed to stdout, before any real assertion runs.

  **Real assertion (after probe passes).** Dispatch `subagent_type: "verifier"` with a prompt asking the agent to use the `Agent` tool to dispatch any sub-agent. Assertion: the agent's response confirms the `Agent` tool is unavailable to it (literal phrase `Agent tool` + `not available` / `cannot` / `subagents do not have` etc. — choose one or two literal phrases from the agent's `verifier.md` body and grep for them). Expected exit: 0.

- [ ] 4.4 — **Canary 4 — Failure-protocol fires on simulated stalled response.** `tests/canary-failure-protocol-fires.sh`. This canary tests the orchestrator-side detection logic, not the verifier itself. Approach:
  - Sandbox a minimal `/run-plan` invocation with `LANDING_MODE=worktree` and a fake verifier dispatch that returns a hard-coded response containing the literal phrase `Tests are running. Let me wait for the monitor.`
  - Either: (a) fork the Phase 3 detection bash block from `skills/run-plan/SKILL.md` into the test as a function, feed it the fake response, assert it sets `FAILED=1` and emits the STOP message; OR (b) run the full `/run-plan` with `--dry-run`-equivalent and inspect the orchestrator's output for the verbatim STOP message.
  - Pick (a) — it's deterministic and doesn't depend on a live `/run-plan` cron. The detection bash logic is small and self-contained; testing it as a function gives the same coverage with 1/100th the runtime.
  - 7 sub-cases:
    - **Sub-case 1**: Stalled phrase present in last 5 lines → FAILED=1, STOP message emitted with `MATCHED` set to the matching phrase.
    - **Sub-case 2** (D3 — empty/short response is FAIL, NOT pass): Empty response (zero bytes) and short response (e.g., 50 bytes "ok done") → FAILED=1, STOP message emitted with `MATCHED` referencing the minimum-length signal `(response shorter than 200 bytes — empty or stub)`. Closes #180's empty-response hole.
    - **Sub-case 3**: Normal response with test summary, ≥200 bytes, no stalled phrase in last 5 lines → FAILED=0, no STOP.
    - **Sub-case 4**: Response that mentions the literal word `BashOutput` in **earlier** lines (e.g., the verifier explaining "BashOutput is not in my allowlist") but ends cleanly with a test summary in the last 5 lines → FAILED=0, no STOP. Regress test for C2's bare-substring removal — bare `bashoutput` no longer triggers, AND last-N-lines anchoring prevents earlier-prose contamination.
    - **Sub-case 5**: Response with `waiting on bashoutput` in the last 5 lines → FAILED=1, STOP. Confirms the behavioral phrase is a live trigger (replacement for the removed bare substring).
    - **Sub-case 6** (N3 — threshold-calibration positive cases, all ≥200 bytes, all expected FAILED=0). Three realistic "tests skipped" attestations, each ≥200 bytes:
      - 6a: `Tests: skipped — no test infra detected. TEST_MODE=skipped per zskills-config.json. Phase scope is markdown-only (CLAUDE.md edits + plan refinement). No code surface to exercise. Verification consists of grep audits of section anchors — passed.`
      - 6b: `Tests: skipped — phase scope is content-only (CHANGELOG entry + frontmatter status update). I read the diff; CHANGELOG entry resolves to today's date and references the correct issues. PLAN_INDEX.md move is correct. No assertion failures.`
      - 6c: `Tests: skipped — TEST_MODE=skipped per zskills-config.json. The phase touches only references/ docs; the test config explicitly excludes references/ from the test surface. Verified the markdown renders without warnings via mdformat --check.`
      Each ≥200 bytes; each must produce FAILED=0 (no STOP). These calibrate the threshold against realistic legitimate-skip prose so the cutoff is example-driven, not arbitrary.
    - **Sub-case 7** (N3 — threshold-calibration negative cases, all <200 bytes, all expected FAILED=1, MATCHED references min-length signal). Three stub responses:
      - 7a: `ok done` (8 bytes)
      - 7b: `verified` (8 bytes)
      - 7c: `Tests: passed` (13 bytes)
      Each MUST trigger FAILED=1 with `MATCHED="(response shorter than 200 bytes — empty or stub)"`. Confirms the 200-byte cutoff catches stubs that read superficially-positive but provide no attestation.

- [ ] 4.5 — **Register all 4 canaries in `tests/run-all.sh`** via `run_suite "name" "tests/X.sh"` lines. Verify by `bash tests/run-all.sh` running them as part of the suite.

### Design & Constraints

- **Sandbox-based.** Each canary creates its own `WORK_BASE="/tmp/zskills-tests/$(basename "$REPO_ROOT")/<suite>-cases"` and cleans up at end. No global state.
- **No real `/run-plan` cron in canaries.** Pure unit-test shape: function-level, no in-session scheduling.
- **No `kill -9, killall, pkill, fuser -k`.** If a canary leaves a process alive (it shouldn't — no long-running ops), let it timeout naturally; do NOT force-kill.
- **Capture canary output to `/tmp/zskills-tests/$(basename "$(pwd)")/<canary-name>.log`**, not piped.
- **Pass/fail helpers** from existing test conventions (`pass`, `fail`); numbered cases.
- **Commit boundary (Phase 4):** single commit. Files: `tests/canary-verifier-tools-allowlist.sh`, `tests/canary-verifier-bash-no-background.sh`, `tests/canary-verifier-no-subdispatch.sh`, `tests/canary-failure-protocol-fires.sh`, `tests/run-all.sh` (4 new `run_suite` lines). NO source skill edits in this commit.

### Acceptance Criteria

- [ ] AC-4.1 — `bash tests/canary-verifier-tools-allowlist.sh` exits 0 with all sub-cases PASS.
- [ ] AC-4.2 — `bash tests/canary-verifier-bash-no-background.sh` exits 0 with both Case A and Case B PASS.
- [ ] AC-4.3 — `bash tests/canary-verifier-no-subdispatch.sh` exits 0 with the no-Agent-tool assertion PASS.
- [ ] AC-4.4 — `bash tests/canary-failure-protocol-fires.sh` exits 0 with all 7 sub-cases PASS (sub-cases 1-5 + threshold-calibration positive 6a/6b/6c + negative 7a/7b/7c per N3).
- [ ] AC-4.5 — `grep -F 'canary-verifier-tools-allowlist' tests/run-all.sh` && `grep -F 'canary-verifier-bash-no-background' tests/run-all.sh` && `grep -F 'canary-verifier-no-subdispatch' tests/run-all.sh` && `grep -F 'canary-failure-protocol-fires' tests/run-all.sh` — all return at least 1 line each.
- [ ] AC-4.6 — Full test suite (resolve `$FULL_TEST_CMD`) passes; zero new failures vs. baseline. Verify the 4 canaries appear in the run-all output as PASS lines.

### Dependencies

- Phases 1, 2, 3 must be complete.

---

## Phase 5 — `/update-zskills` install path + end-to-end consumer test

### Goal

**Extend `/update-zskills` Step C ("Fill hook gaps")** — the existing block at `skills/update-zskills/SKILL.md:816-836` that copies `$PORTABLE/hooks/<name>.sh` to `.claude/hooks/<name>.sh`. The extension does TWO things in the same step (NOT a sibling step):
1. The hook-copy loop iterates an extended source list that includes the new `validate-bash-no-background.sh` and `validate-bash-readonly.sh` alongside the existing `block-*` and `warn-config-drift.sh` hooks.
2. A new agent-copy block immediately after the hook copy iterates `$PORTABLE/.claude/agents/*.md` and copies missing/changed ones to the consumer's `.claude/agents/`.

Step C's narrative changes from "Fill hook gaps" to "Fill hook + agent gaps". Audit step in Step 3's summary lists installed agents alongside hooks. End-to-end: a fresh consumer install picks up the verifier agent definition and both hook scripts; the structural defense is live after a session restart (per the auto-discovery semantics — install path emits a WARN line about this).

### Work Items

- [ ] 5.1 — **Edit `skills/update-zskills/SKILL.md` Step C — Fill hook gaps** (currently lines ~816-836). Read the section in full. The existing block copies hooks from `$PORTABLE/hooks/` to `.claude/hooks/`. Two extensions to that same step:

  **Extension 1 — extend the hook list.** The two new validation hooks (`validate-bash-no-background.sh`, `validate-bash-readonly.sh`) live at `$PORTABLE/hooks/` (sister of `block-unsafe-generic.sh` etc.) and install to `$PROJECT_DIR/.claude/hooks/` (sister of `block-unsafe-generic.sh` etc.). Edit the Step C hook-copy loop's source list to include them. No new directory, no new install pattern.

  **Extension 2 — agent-copy block, immediately after the hook copy, before the "Explain what each hook does" prose.** Append:

  > **Custom subagent definitions.** After hook copy, copy missing or changed agent definitions from `$PORTABLE/.claude/agents/*.md` to `$PROJECT_DIR/.claude/agents/`. `cp -a` preserves mode bits + mtime. The agent frontmatter references `$CLAUDE_PROJECT_DIR/.claude/hooks/<name>.sh` — those paths are fixed, so the hook-copy step (above) is a hard prerequisite.
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
  >   # Auto-discovery WARN — REQUIRED at session-restart-sensitive boundary.
  >   echo "WARN: agent definitions auto-discover at session start. Restart Claude Code (or open a new session) before invoking verifier-using skills (/run-plan, /commit, /fix-issues, /do, /verify-changes). There is no in-session reload command."
  > fi
  > ```
  >
  > **Why install hooks under `.claude/hooks/`:** existing zskills convention. `.claude/scripts/` does NOT exist in zskills; verified by `ls /workspaces/zskills/.claude/hooks/` (4 sibling hook scripts present) and `ls /workspaces/zskills/.claude/scripts/` (ENOENT). The agent frontmatter references `$CLAUDE_PROJECT_DIR/.claude/hooks/validate-bash-*.sh`. Consumers who customize hooks must edit the agent frontmatter.
  >
  > **No settings.json wiring needed for agents.** Claude Code auto-discovers `.claude/agents/*.md` at session start (project-local priority 3 per `code.claude.com/docs/en/sub-agents`). The frontmatter `hooks:` field is per-agent — it does NOT register in `.claude/settings.json`. The Step C settings.json merge (lines ~873-893) is unaffected — no new canonical hook entries are added (the `validate-bash-*.sh` hooks fire only via agent-frontmatter, NOT as global PreToolUse on every Bash).
  >
  > **Bash regex parse only — no `jq`.** The cp loop uses pure bash; no JSON parsing needed.

  Verified: `/workspaces/zskills/skills/update-zskills/SKILL.md:818` opens with "Copy missing hooks from `$PORTABLE/hooks/` to `.claude/hooks/`" — the extension lands cleanly inside that block.

- [ ] 5.2 — **Add an audit/diff step.** In Step 3 ("Pull Latest and Update" / install audit summary, locate by reading the relevant section of `skills/update-zskills/SKILL.md`), include the agent inventory in the structured summary:

  > Installed agents:
  > - verifier (from .claude/agents/verifier.md, structural tools allowlist + Bash-no-background hook)
  > - commit-reviewer (from .claude/agents/commit-reviewer.md, read-only)
  >
  > Installed hook scripts:
  > - .claude/hooks/validate-bash-no-background.sh
  > - .claude/hooks/validate-bash-readonly.sh
  >
  > Drift check: each .md is byte-equivalent to source ($PORTABLE/.claude/agents/<name>.md).
  > Drift check: each hook script is byte-equivalent to source ($PORTABLE/hooks/<name>.sh).

  Implement the drift-check loop in bash, comparing via `cmp -s`. Report any drift with `WARN: agent <name> has diverged from source — consumer customization or stale install`.

- [ ] 5.3 — **Bump `skills/update-zskills/SKILL.md` `metadata.version`.** Verify via `bash scripts/skill-version-stage-check.sh`. Mirror.

- [ ] 5.4 — **Add a test for the install path.** `tests/test-update-zskills-agent-install.sh`. Sandbox-based:
  - Set up a fake consumer repo at `$WORK_BASE/consumer/` with empty `.claude/`.
  - Set `$PORTABLE` to point at the zskills source clone (or a sandbox mirror with `.claude/agents/verifier.md` + the two hook scripts).
  - Run the relevant section of the install flow (extract the Step C agent-copy block as a callable bash function or invoke `/update-zskills` against the sandbox).
  - Assert `[ -f "$WORK_BASE/consumer/.claude/agents/verifier.md" ]`, `[ -f "$WORK_BASE/consumer/.claude/agents/commit-reviewer.md" ]`, `[ -x "$WORK_BASE/consumer/.claude/hooks/validate-bash-no-background.sh" ]`, `[ -x "$WORK_BASE/consumer/.claude/hooks/validate-bash-readonly.sh" ]`. Also assert `[ ! -d "$WORK_BASE/consumer/.claude/scripts" ]` — the wrong-path directory must NOT have been created.
  - Assert the agent file's content is byte-equivalent to source: `cmp -s "$PORTABLE/.claude/agents/verifier.md" "$WORK_BASE/consumer/.claude/agents/verifier.md"`.
  - Re-run the install flow against the same consumer (idempotent path); assert no errors and no spurious "Updated" lines.
  - Modify the consumer's `verifier.md` (simulate consumer customization); re-run install; assert "Updated agent: verifier.md" line appears (or document the consumer-customization handling explicitly).

- [ ] 5.5 — **Register the new test in `tests/run-all.sh`** via `run_suite "agent-install" "tests/test-update-zskills-agent-install.sh"`.

- [ ] 5.6 — **Mirror `skills/update-zskills/`** via `bash scripts/mirror-skill.sh update-zskills`.

### Design & Constraints

- **`/update-zskills` is the only consumer-facing install path.** Consumers do NOT manually copy `.claude/agents/` — that leaves them out of sync. Step C (extended) is the canonical install.
- **Idempotent.** Running `/update-zskills` twice on the same consumer with no source changes is a no-op (no spurious "Updated" lines, no diffs). `cmp -s` gates the copy.
- **Consumer-customization handling:** if a consumer edits `.claude/agents/verifier.md` (e.g., to add a project-specific allowlist tool), the next install OVERWRITES with source. Document this in the extended Step C prose: "Consumer customizations to `.claude/agents/<name>.md` are overwritten on each install. Customize via a different agent name (e.g., `verifier-myproject.md`) or via per-invocation overrides." Tradeoff: consumer customization vs. structural-fix integrity. Choose integrity (overwrite) — the structural restrictions are safety-critical.
- **No `settings.json` modifications in this phase.** `.claude/agents/` is auto-discovered.
- **No `jq` introduced into update-zskills.** Bash regex only (existing convention).
- **PostToolUse `warn-config-drift.sh` hook** must continue to fire correctly across the new agent files. Verify by reading `hooks/warn-config-drift.sh` and confirming its file-pattern matcher includes `.claude/agents/` (or extend it if needed — but extension is OUT OF SCOPE for this plan; the existing PostToolUse on `Edit/Write` fires on `.claude/agents/*.md` because the matcher is tool-name-based, not path-based).
- **Commit boundary (Phase 5):** single commit. Files: `skills/update-zskills/SKILL.md` (Step C extension + audit step + `metadata.version` bump), `.claude/skills/update-zskills/SKILL.md` (mirror), `tests/test-update-zskills-agent-install.sh` (new test), `tests/run-all.sh` (1 new `run_suite` line).

### Acceptance Criteria

- [ ] AC-5.1 — Step C is **extended in place** (not sibling-stepped): the existing Step C heading at `skills/update-zskills/SKILL.md` (`#### Step C — Fill hook gaps`) is still present AND the section now contains an agent-copy sub-block. Verify: `grep -F '#### Step C' skills/update-zskills/SKILL.md` returns 1+ line AND `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F '.claude/agents'` returns 1+ line.
- [ ] AC-5.2 — Auto-discovery WARN line is present in the Step C agent-copy block: `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F 'WARN: agent definitions auto-discover at session start'` returns 1 line. The WARN line directs the user to "Restart Claude Code (or open a new session)" and explicitly states there is no in-session reload command. AC asserts the WARN line does NOT mention `/agents reload` (a fictional command in current Claude Code 2.1.126 — verified by `claude -p "/agents reload" --output-format text` returning "isn't available"): `awk '/^#### Step C/,/^#### Step [^C]/' skills/update-zskills/SKILL.md | grep -F '/agents reload'` returns no output, OR returns only the explicit "no in-session reload command" disclaimer.
- [ ] AC-5.3 — `bash tests/test-update-zskills-agent-install.sh` exits 0 with all sub-cases PASS (install fresh, install idempotent, install over consumer customization).
- [ ] AC-5.4 — `bash scripts/skill-version-stage-check.sh` exits 0 against the staged set (covers `skills/update-zskills/`).
- [ ] AC-5.5 — `diff -rq skills/update-zskills/ .claude/skills/update-zskills/` returns no output.
- [ ] AC-5.6 — `grep -F 'test-update-zskills-agent-install' tests/run-all.sh` returns 1+ line.
- [ ] AC-5.7 — End-to-end consumer install verification (R8 — no `install.sh` entry point in zskills): dispatch `/update-zskills` against a sandbox `$PORTABLE` clone in a scratch consumer directory. Confirm `.claude/agents/verifier.md`, `.claude/agents/commit-reviewer.md`, `.claude/hooks/validate-bash-no-background.sh`, `.claude/hooks/validate-bash-readonly.sh` all land in the scratch dir AND the WARN line about auto-discovery appears in the install transcript. Capture transcript to `/tmp/zskills-tests/$(basename "$(pwd)")/manual-install.log`.
- [ ] AC-5.8 — Hook scripts install to `.claude/hooks/`, NOT `.claude/scripts/`: in the scratch consumer, `[ -f .claude/hooks/validate-bash-no-background.sh ] && [ -f .claude/hooks/validate-bash-readonly.sh ] && [ ! -d .claude/scripts ]`.
- [ ] AC-5.9 — Full test suite passes; zero new failures vs. baseline.

### Dependencies

- Phases 1, 2, 3, 4 must be complete.

---

## Phase 6 — Documentation, CLAUDE.md, CHANGELOG, final verification

### Goal

Finalize documentation: confirm CLAUDE.md rule from Phase 1.7 is in place; add a CHANGELOG entry under today's date; verify every modified skill's `metadata.version` is fresh; verify the full plan-level closure of #176 and #180.

### Work Items

- [ ] 6.1 — **Verify CLAUDE.md rule** from Phase 1.7 is in place: `grep -F 'Verifier-cannot-run is a verification FAIL' CLAUDE.md`. If not, add it now (idempotent).

- [ ] 6.2 — **Add CHANGELOG.md entry** under today's date (`TZ=America/New_York date +%Y-%m-%d`). The CHANGELOG entry uses **schematic placeholders only** (e.g., `YYYY-MM-DD`, `YYYY.MM.DD+HHHHHH`); concrete date+hash literals are forbidden in plan text and CHANGELOG to avoid colliding with the #179 forbidden-literals scan. Verbatim shape (with `YYYY-MM-DD` resolved to today's date at write time, NOT in the plan source):

  > ## YYYY-MM-DD
  >
  > - **Verifier subagent — structural defense.** Replaced the prose-only `run_in_background: true` warning (PR #148) with a Claude Code custom-subagent definition at `.claude/agents/verifier.md` (tools allowlist excluding `Monitor`/`BashOutput`) plus a frontmatter `PreToolUse` hook on `Bash` rejecting `run_in_background: true` (`hooks/validate-bash-no-background.sh`, installed to `.claude/hooks/`). New `commit-reviewer.md` agent for read-only /commit reviews (extra hook rejecting state-mutating Bash). Five dispatch sites migrated to explicit `subagent_type:` parameters: `/run-plan` Phase 3, `/commit` Phase 5 step 3, `/fix-issues` per-issue verification, `/do` Phase 3 (code + content paths), `/verify-changes` self-dispatch. `/run-plan` Phase 3 gains a Failure Protocol clause that STOPs on stalled-string match (last 5 lines of response) plus a 200-byte minimum-length signal — whitelist of 7 phrases including "let me wait for the monitor"; bare `bashoutput` substring excluded to avoid false-positives on legitimate prose. `/update-zskills` Step C extended to install `.claude/agents/<name>.md` and the two `validate-bash-*.sh` hooks alongside existing hook copies. CLAUDE.md gains "Verifier-cannot-run is a verification FAIL" rule. Closes #176, #180.

- [ ] 6.3 — **Verify all 5 modified skills have fresh `metadata.version`** (one per Phase 2 + 3 + 5):
  - `run-plan` (Phase 2)
  - `commit`, `fix-issues`, `do`, `verify-changes` (Phase 3)
  - `update-zskills` (Phase 5)

  `bash scripts/skill-version-stage-check.sh` exits 0 (covers all skills).

- [ ] 6.4 — **Verify the 6 mirror dirs are byte-equivalent to source:**
  ```bash
  for s in run-plan commit fix-issues do verify-changes update-zskills; do
    diff -rq "skills/$s/" ".claude/skills/$s/" || exit 1
  done
  ```

- [ ] 6.5 — **Final acceptance verification — closure of #176 and #180:**
  - For #176: confirm `.claude/agents/verifier.md` excludes `Monitor` AND `BashOutput`; confirm hook script is installed and a sample input with `run_in_background: true` blocks; confirm at least one canary (Phase 4) end-to-end PASSES.
  - For #180: confirm `/run-plan` Phase 3 has the Failure Protocol clause with all 7 stalled-string whitelist phrases AND the verbatim STOP message; confirm Phase 4 canary 4 (`canary-failure-protocol-fires.sh`) PASSES with all 7 sub-cases (5 baseline + 2 threshold-calibration groups per N3).

- [ ] 6.6 — **Run the full test suite one final time.** Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`. Compare to baseline. Zero new failures.

- [ ] 6.7 — **File follow-up issue (N3 — extract failure-protocol shared library).** Open a GitHub issue against `zeveck/zskills-dev` titled `Extract verifier failure-protocol detection into shared library` with body:

  > Phase 2 of VERIFIER_AGENT_FIX scoped the verifier-empty/stalled detection (stalled-string whitelist + 200-byte minimum-length signal) to `/run-plan` only — the most common verifier-dispatch site, which captures the recurring failure mode from PR #175. The other four dispatch sites (`/commit` Phase 5 step 3, `/fix-issues` per-issue, `/do` Phase 3 code path, `/verify-changes` self-dispatch) gained explicit `subagent_type:` parameters but NOT the orchestrator-side detection logic.
  >
  > Follow-up: extract the detection bash block (LAST5 + STALLED_PATTERNS + MIN_RESPONSE_BYTES + STOP message) into `hooks/verify-response-validate.sh` (or a sibling location), callable from all 5 verifier-dispatching skills. Each skill sources the library after its `Agent` dispatch returns.
  >
  > Tradeoff this defers: ergonomics (one source of truth) and consistency (failure mode is the same for all 5 sites). The current scoped fix is acceptable because (a) the recurring failure mode is concentrated at `/run-plan` Phase 3 dispatches, (b) the structural defense at the `verifier.md` allowlist + PreToolUse hook level applies to ALL 5 sites uniformly (Layer 1 + 2 are universal; Layer 3 detection is `/run-plan`-specific). The library extraction is pure refactor — same behavior, broader application.

- [ ] 6.8 — **File follow-up issue (N9 — structural-detection 8th rule).** Open a GitHub issue titled `Add structural Monitor/BashOutput tool-name appearance detection as 8th failure-protocol rule` with body:

  > Phase 2's failure-protocol clause uses a 7-phrase whitelist (case-insensitive substring against last 5 lines of the verifier response). Whitelist-by-enumeration has finite recall: 4 plausible miss-cases ("I'll watch the bashoutput", "Going to monitor that backgrounded job", "Let me check on it in a moment", etc.) bypass detection.
  >
  > Follow-up: add an 8th rule — last 10 lines contain literal tool-name `Monitor` or `BashOutput` AND do NOT contain any escape-clause string ('allowlist', 'excluded', 'not in tools', 'cannot use'). Catches the structural anti-pattern (verifier names the tool in a polling context) without enumerating phrases.
  >
  > Tradeoff: false-positive on unusual prose ("I considered using BashOutput but rejected it because…"); mitigation is the tight last-10-lines anchor + escape-clause whitelist. Defer because the 7-phrase whitelist already catches the canonical PR #175 failure phrase and Codex-equivalent variants; this is hardening, not closure.

- [ ] 6.9 — **Plan completion bookkeeping:** update plan frontmatter `status: complete` and `completed: <today>`; move plan from `plans/PLAN_INDEX.md` "Active" to "Complete" section.

### Design & Constraints

- **No new code in Phase 6.** Documentation, version verification, mirror verification, plan-completion bookkeeping only.
- **CHANGELOG entry is for the entire plan**, not per-phase. One entry under today's date covering all 6 phases at the conceptual level (the structural-fix story).
- **#179 forbidden-literals scan compliance.** Plan text uses only schematic placeholders (`YYYY-MM-DD`, `YYYY.MM.DD+HHHHHH`); CHANGELOG entry resolves `YYYY-MM-DD` to today at write time but uses only the schematic placeholder for the version-string format. AC-6.10 below asserts the scan exits 0 against the worktree state.
- **Commit boundary (Phase 6):** single commit. Files: `CLAUDE.md` (idempotent verification of the rule), `CHANGELOG.md` (new entry), `plans/VERIFIER_AGENT_FIX.md` (frontmatter `status: complete`), `plans/PLAN_INDEX.md` (move to Complete section). NO source skill edits, NO `metadata.version` bumps in this commit.

### Acceptance Criteria

- [ ] AC-6.1 — `grep -F 'Verifier-cannot-run is a verification FAIL' CLAUDE.md` returns 1+ line.
- [ ] AC-6.2 — `head -20 CHANGELOG.md | grep -F 'Verifier subagent — structural defense'` returns 1 line, AND the entry's date heading is today (`TZ=America/New_York date +%Y-%m-%d`).
- [ ] AC-6.3 — `grep -F 'Closes #176, #180' CHANGELOG.md` returns 1+ line.
- [ ] AC-6.4 — `bash scripts/skill-version-stage-check.sh` exits 0 against the worktree state.
- [ ] AC-6.5 — `for s in run-plan commit fix-issues do verify-changes update-zskills; do diff -rq "skills/$s/" ".claude/skills/$s/" || exit 1; done` returns no output.
- [ ] AC-6.6 — All 4 Phase 4 canaries PASS (`bash tests/canary-verifier-tools-allowlist.sh && bash tests/canary-verifier-bash-no-background.sh && bash tests/canary-verifier-no-subdispatch.sh && bash tests/canary-failure-protocol-fires.sh` exits 0).
- [ ] AC-6.7 — Full test suite passes; zero new failures vs. baseline. Capture to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`.
- [ ] AC-6.8 — Plan frontmatter `status: complete`; `plans/PLAN_INDEX.md` lists the plan in the Complete section.
- [ ] AC-6.9 — `gh issue view 176 --repo zeveck/zskills-dev` and `gh issue view 180 --repo zeveck/zskills-dev` are ready to close (still open at PR-merge time; orchestrator closes with the merge commit message `Closes #176, #180`).
- [ ] AC-6.10 — Forbidden-literals enforcement (#179): run `bash hooks/warn-config-drift.sh` against each modified plan/skill file as if just edited (simulate `tool_input.file_path` JSON via stdin: `printf '{"tool_input":{"file_path":"%s"}}' "$f" | bash hooks/warn-config-drift.sh`); assert no WARN line about forbidden literals fires for any file in the change set. The CHANGELOG entry's `YYYY-MM-DD` MUST resolve to a real date at write time, but the plan source and bare-fenced examples in modified skills use only schematic placeholders. (N7 fix — the round-1 spec referenced a non-existent standalone `forbidden-literals-scan.sh` script with a `skip-with-issue` escape hatch. Verified: `find . -name 'forbidden-literals*'` returns only `tests/fixtures/forbidden-literals.txt`; no standalone scan script exists. The forbidden-literals enforcement primitive that DOES exist is `hooks/warn-config-drift.sh`, which is the live edit-time gate. AC reuses that primitive for deterministic verification — no skip-with-issue.)

### Dependencies

- Phases 1, 2, 3, 4, 5 must be complete.

---

## Plan Quality

| Round | Reviewer Findings | Devil's Advocate Findings | After Dedup | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1     | 13                | 10                        | 17          | 17       |
| 2     | 6                 | 7                         | 10          | 9        |

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

Round-2 new findings: N1 (HIGH — `/agents reload` is fictional in Claude Code 2.1.126; verified `claude -p "/agents reload"` returns "isn't available"), N2 (HIGH — `--agents` CLI flag takes inline JSON not file paths; verified via `claude --help`), N3 (MEDIUM — Failure Protocol scoped only to `/run-plan`; the other 4 verifier-dispatching skills unprotected), N4 (MEDIUM — Plan Quality table 19-vs-17 contradiction; honest count is 17), N5 (MEDIUM — C5 footnote misstated current state; verified all 7 phrases return zero matches today), N6 (HIGH — readonly-bash hook bypassable via env-var prefix, &&, subshell, pipe; verified empirically), N7 (MEDIUM — AC-6.10 referenced non-existent forbidden-literals-scan script; the live primitive is `hooks/warn-config-drift.sh`), N8 (MEDIUM — Phase 6.5 said "all 6 phrases", every other site says 7), N9 (LOW — whitelist enumeration has finite recall; structural 8th rule deferred to follow-up issue), N10 (LOW — Phase 1.4 case 6 used `\\n` literal that isn't a real newline and duplicated case 7).

Resolved this round (9): N1, N2, N3 (option a — scoped + follow-up issue work item 6.7), N4, N5, N6 (option b — word-boundary regex), N7, N8, N10.

Justified-not-fixed (1): N9 — deferred per round-2 review's explicit "Acceptable to defer with issue if scope-creep is concern" allowance; Phase 6.8 work item files the follow-up GitHub issue.

Restructuring in Round 2:
- Phase 1.1 canary spec rewritten end-to-end (N2): canonical two-script flow; `--agents` inline-JSON path dropped from spec; Phase 4.1 + 4.3 canaries gain probe-step that converts silent agent-not-discovered into a loud header.
- Phase 1.4 test cases renumbered 7→6 (N10).
- Phase 1.5 readonly-hook regex strengthened (N6) with adversarial-bypass BLOCK fixtures + identifier-boundary regress.
- Phase 4.4 sub-cases extended 5→7 (N3 threshold calibration).
- Phase 6 work items added: 6.7 (file follow-up issue per N3) + 6.8 (file follow-up issue per N9); 6.9 = old 6.7 (plan completion bookkeeping).
- Three `/agents reload` references replaced with restart-only recovery prose (N1).
- AC-2.4 footnote rewritten to honest current-state (N5).
- AC-5.2 extended with explicit no-`/agents reload` assertion (N1).
- AC-6.10 rewritten to use `hooks/warn-config-drift.sh` (N7).
