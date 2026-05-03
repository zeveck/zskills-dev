# Plan Report — Verifier Agent Fix

## Phase — 5 /update-zskills install path for verifier.md + 2 new hooks [UNFINALIZED]

**Plan:** plans/VERIFIER_AGENT_FIX.md
**Status:** Completed (verified — round 2 PASS after fix-cycle)
**Worktree:** /tmp/zskills-pr-verifier-agent-fix (branch `feat/verifier-agent-fix`)
**Commits:** a4b0890 (5-file bundle: SKILL.md + mirror + new test + jq-invariant fix + run-all.sh)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 5.1 | Step C extended in place — hook list +2, agent-copy block, consumer-customization note | Done | a4b0890 |
| 5.2 | Audit step (Installed agents + hooks + drift checks) added to install summary | Done | a4b0890 |
| 5.3 | metadata.version bumped to `2026.05.03+a9bbe0` | Done | a4b0890 |
| 5.4 | tests/test-update-zskills-agent-install.sh (new) — 4 sandbox sub-cases | Done | a4b0890 |
| 5.5 | Registered in tests/run-all.sh adjacent to other test-update-zskills-* | Done | a4b0890 |
| 5.6 | Mirror via scripts/mirror-skill.sh — diff -rq clean | Done | a4b0890 |

### Verification
- AC-5.1 — Step C heading is "Fill hook + agent gaps"; section contains `.claude/agents`, `inject-bash-timeout.sh`, `verify-response-validate.sh` references — PASS
- AC-5.2 — auto-discovery WARN line present; only `/agents reload` mention is the explicit "no in-session reload command" disclaimer — PASS
- AC-5.3 — `bash tests/test-update-zskills-agent-install.sh` exit 0, 4/4 sub-cases PASS
- AC-5.4 — `bash scripts/skill-version-stage-check.sh` rc=0
- AC-5.5 — `diff -rq skills/update-zskills/ .claude/skills/update-zskills/` empty
- AC-5.6 — `run_suite "test-update-zskills-agent-install"` registered
- AC-5.7 — **orchestrator-run manual install** in `/tmp/zskills-scratch-consumer` PASS: all 3 artifacts installed (verifier.md + 2 hooks), byte-equivalence, idempotency, WARN line. Transcript at `/tmp/zskills-tests/zskills-pr-verifier-agent-fix/manual-install.log`.
- AC-5.8 — hooks → `.claude/hooks/`, `.claude/scripts/` not created — PASS
- AC-5.9 — `commit-reviewer.md` NOT installed (D'' dropped) — PASS
- AC-5.10 — full suite **2071/2071** PASS (+4 vs pre-Phase-5 baseline 2067/2067)

### Fix-cycle (round 1 → round 2)
Round 1 verifier surfaced AC-5.10 FAIL: `tests/test-update-zskills-version-surface.sh` AC #8 invariant `grep -c 'jq' SKILL.md == 0` tripped on the spec-mandated documentation disclaimer at SKILL.md:886 (`Bash regex parse only — no` + backtick-jq-backtick). The verifier correctly STOPPED instead of papering over.

A fix agent refined the invariant from coarse substring grep to a regex matching actual jq invocation shapes (`| jq`, `$(jq …)`, `` `jq …` ``, `jq -<flag>`, `jq '…'` / `jq "…"`, `^jq +`). Documentation references like `no \`jq\`` are now exempt; the original AC #8 intent (no jq usage in update-zskills) is preserved. This is a legitimate refinement, not a weakening.

The test fix was bundled into the Phase 5 commit (5 files instead of spec's 4) — the cross-plan collision is causally part of "make Phase 5 land" and the spec author didn't anticipate it. Bundling rationale is documented in the commit message.

Round 2 verifier confirmed AC-5.10 PASS (2071/2071) and committed `a4b0890`.

### Notes
- **Step C is now agent-aware.** Future plans that ship `.claude/agents/*.md` get auto-installed via the same path; no skill-source changes needed.
- **No settings.json wiring for agents.** Agent definitions are auto-discovered by Claude Code at session start from `.claude/agents/`. The frontmatter `hooks:` declaration on `verifier.md` wires the Layer 0 PreToolUse hook directly.
- **Consumer-customization handling:** if a consumer edits `.claude/agents/verifier.md` locally, the next `/update-zskills` install OVERWRITES with source (idempotent `cmp -s` gate ensures only changed files are touched). Consumers who want custom verifier behavior should fork the source skill and ship it alongside zskills, not edit the installed copy.
- **Auto-discovery WARN is critical.** New verifier-using skills (`/run-plan`, `/commit`, `/fix-issues`, `/do`, `/verify-changes`) won't see the verifier agent until session restart — there's no in-session reload mechanism in Claude Code. The WARN line communicates this expectation explicitly so consumers don't get cryptic "no such agent" errors.

### Dependencies satisfied
- Phases 1, 2, 3, 4 — all done

### Downstream
- Phase 6: CHANGELOG entry + Anthropic upstream issue + plan completion bookkeeping. Phase 6 is the final phase — `/land-pr` with `--auto` enables PR #189 automerge.

---

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
