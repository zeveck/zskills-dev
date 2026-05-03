# Plan Report — Verifier Agent Fix

## Phase — 4 Canaries: tools-allowlist, timeout-injection, failure-protocol script [UNFINALIZED]

**Plan:** plans/VERIFIER_AGENT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-verifier-agent-fix (branch `feat/verifier-agent-fix`)
**Commits:** b2a968e

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 4.1 | Canary 1 (`canary-verifier-agent-discovery-part1.sh` + `part2.sh`) — already shipped, retained | Done | (Phase 1) |
| 4.2 | Canary 2 — `tests/canary-verifier-timeout-injection.sh` — 7 assertions (parity / frontmatter wiring / 3 invocation cases) | Done | b2a968e |
| 4.3 | Canary 3 — `tests/canary-verify-response-validate.sh` — 11 sub-cases A-G | Done | b2a968e |
| 4.4 | Register canaries 2 & 3 in `tests/run-all.sh` (2 new `run_suite` lines) | Done | b2a968e |

### Verification
- AC-4.1: `canary-verifier-agent-discovery-part1.sh` exit 0 (install-fixture script per Phase 1 design)
- AC-4.2: `canary-verifier-timeout-injection.sh` exit 0 — 7/7 assertions PASS
- AC-4.3: `canary-verify-response-validate.sh` exit 0 — 11/11 sub-cases PASS
- AC-4.4: both `run_suite` lines present at lines 42-43
- AC-4.5: full suite **2067/2067 PASS** (+18 vs pre-Phase-4 baseline 2049/2049)

### Notes
- **Live-dispatch property scope-out (Canary 2)**: the spec's "probe step" (live `Agent` dispatch returning `CANARY-PROBE-OK`) isn't runnable from pure shell. Canary 2 asserts everything CI-verifiable — source/mirror parity, frontmatter wiring (`.claude/agents/verifier.md` PreToolUse Bash matcher with the hook command), and the hook script's behavior across 3 invocation cases (probe-equivalent / real-injection / no-op on already-sufficient timeout). The live end-to-end property is exercised every time a real `/run-plan` Phase 3 verifier dispatch runs against a long-running test suite.
- **Phase 3.5 auto-correction**: 1 PLAN-TEXT-DRIFT token detected and re-confirmed independently — `phase=4 bullet=4.3-G-a field=byte-count plan=8 actual=7` (`"ok done"` is 7 chars, not 8). 13% drift falls in the 10-20% band → auto-corrected with audit comment inline. Behaviorally harmless (assertion is `<200`).
- **Threshold-calibration matrix** (sub-cases F + G) makes the 200-byte cutoff example-driven instead of arbitrary — three realistic ≥200-byte "tests skipped" attestations (F) and three sub-200-byte stubs (G) demonstrate the threshold's real-world margin.

### Dependencies satisfied
- Phase 1 (verifier.md + Layer 0 + Layer 3 hooks) — done
- Phase 2 (`/run-plan` Layer 3 wired) — done
- Phase 3 (4 other verifier-dispatching skills wired) — done

### Downstream
- Phase 5: `/update-zskills` install path for `verifier.md` + the 2 hooks. After Phase 5 lands, consumer repos receive the structural fix automatically.
- Phase 6: CHANGELOG, file Anthropic upstream issue, plan completion.

---

## Phase — 3 Migrate /commit, /fix-issues, /do, /verify-changes [UNFINALIZED]

**Plan:** plans/VERIFIER_AGENT_FIX.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-verifier-agent-fix (branch `feat/verifier-agent-fix`)
**Commits:** d6690d0 (3-A /commit), 285bc1d (3-B /fix-issues), cf2fc56 (3-C /do), 5919ea9 (3-D /verify-changes)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 3.1 | /commit Phase 5 step 3 — subagent_type:"verifier" + Layer 3 + read-only preamble | Done | d6690d0 |
| 3.2 | /commit metadata.version bump (→ `2026.05.03+e8e557`) + mirror | Done | d6690d0 |
| 3.3 | /fix-issues Dispatch protocol — subagent_type:"verifier" + Layer 3 | Done | 285bc1d |
| 3.4 | /fix-issues metadata.version bump (→ `2026.05.03+8c4e2f`) + mirror | Done | 285bc1d |
| 3.5 | /do Phase 3 — TWO dispatch sites (code-changes + content-only) wired | Done | cf2fc56 |
| 3.6 | /do metadata.version bump (→ `2026.05.03+27f0e7`) + mirror | Done | cf2fc56 |
| 3.7 | /verify-changes Dispatch protocol — subagent_type:"verifier" + freshness modes | Done | 5919ea9 |
| 3.8 | /verify-changes metadata.version bump (→ `2026.05.03+d5c06b`) + mirror | Done | 5919ea9 |
| 3.9 | Out-of-scope skill audit — none modified outside migration scope | Done | (verified) |

### Verification
- Test suite: PASSED (2049 / 2049, parity with pre-Phase-3 baseline)
- All 12 acceptance criteria PASS (independently re-verified by `verifier` subagent)
- Hygiene: no `.worktreepurpose` / `.zskills-tracked` / `.landed` / `.test-*.txt` files staged or tracked
- Mirror parity: all 4 `skills/<name>/` ↔ `.claude/skills/<name>/` clean
- Freshness mode: `single-context fresh-subagent` (verifier subagent ran inline, no sub-sub-agents — categorical Anthropic design)

### Notes
- Layer 3 invocation (`bash $CLAUDE_PROJECT_DIR/.claude/hooks/verify-response-validate.sh`) is now wired uniformly across all 5 verifier-dispatching skills (Phase 2 wired `/run-plan`, Phase 3 wires the other 4).
- `/commit` retains the existing read-only prose verbatim (defense-in-depth + downstream documentation), with the new Dispatch-shape callout stacked above and Layer 3 invocation block stacked below.
- `/do` has two distinct dispatch sites (code-changes path AND content-only path); both received the migration.
- `/verify-changes` documents three freshness modes in its dispatch-protocol section so verification reports can self-classify.
- PR #148's prose `run_in_background` warnings are preserved across all 4 originally-warned skills (defense-in-depth complement to the structural Layer 0+3 fix).

### Dependencies satisfied
- Phase 1 (`.claude/agents/verifier.md`, `hooks/verify-response-validate.sh`, `hooks/inject-bash-timeout.sh`) — done
- Phase 2 (`/run-plan` migration is the model the other 4 follow) — done

### Downstream
- Phase 4 (canaries) will exercise the new Layer 0 timeout-injection hook, the verifier tools allowlist, and the Layer 3 failure-protocol script.
- Phase 5 (`/update-zskills` install path) will ensure consumer repos receive `verifier.md` + both new hooks via `/update-zskills`.

## Phase — 1+2 Backfill (already landed in prior session)

Phases 1 and 2 landed before this report file existed. Brief backfill for completeness:
- **Phase 1** (`89d1b57` + D'' rework `86a25c8`): Verifier agent file at `.claude/agents/verifier.md` (full tools allowlist) + Layer 0 PreToolUse hook (`inject-bash-timeout.sh`) + Layer 3 script (`verify-response-validate.sh`). L1+L2 architecture (allowlist exclusion + bg-rejection hook + commit-reviewer.md) dropped per user pushback — D'' addresses root cause directly. Manual canary PASSED 2026-05-03 against Claude Code 2.1.126.
- **Phase 2** (`636eccb`): `/run-plan` Phase 3 verifier dispatch migrated to `subagent_type: "verifier"` + Layer 3 invocation pipe + STOP on exit 1. metadata.version bumped to `2026.05.03+82aa34`. Conformance tripwires +4. Tests 2049/2049 PASS.
