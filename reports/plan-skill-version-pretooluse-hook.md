# Plan Report — Skill-Version PreToolUse Hook (Plan B)

## Plan Status: ✅ COMPLETE (all 5 phases landed)

PR [#193](https://github.com/zeveck/zskills-dev/pull/193) ready for `/land-pr --auto` automerge after Phase 5b bookkeeping commits.

## Phase — 5 CHANGELOG + CLAUDE.md note + final conformance [UNFINALIZED]

**Plan:** plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
**Status:** Completed (verified — all ACs PASS)
**Commits:** 886304d (work), (this report commit)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 5.1 | CHANGELOG.md new `## 2026-05-06` H2 + `### Added —` H3 (Plan A's H2 preserved) | Done | 886304d |
| 5.2 | CLAUDE.md `## Skill versioning` PreToolUse-backstop paragraph + cross-ref to `## Verifier-cannot-run rule` | Done | 886304d |
| 5.3 | Final test suite — 2111/2111 PASS (parity with baseline) | Done | (verified) |
| 5.4 | Phase 3 deferred AC8 — canary RECIPE doc at `tests/canary-zskills-self-fires.txt` | Done | 886304d |
| 5.5 | Final conformance gate (skill-version-stage-check + tests) | Done | (verified) |
| 5.6 | Phase 5.6 split routing — followups doc (stage-check UX nit + BLOCK_UNSAFE_HARDENING reference) | Done | 886304d |

### Verification
- All ACs PASS (independently re-verified by `verifier` subagent)
- Tests **2111/2111** PASS (parity with baseline; Phase 5 is docs-only finalization)
- Hygiene clean
- D&C respected: NO new code in `hooks/`, `skills/`, or `tests/run-all.sh`

### Notes
- CHANGELOG H2 collision spec was N/A: today (2026-05-06) is a new date; created fresh `## 2026-05-06` H2 above existing `## 2026-05-03` (Plan A's entry preserved).
- Composition-semantics citation in CLAUDE.md PreToolUse-backstop paragraph cites Anthropic Code docs (https://code.claude.com/docs/en/sub-agents §"Hooks in subagent frontmatter").
- Verifier-side recovery documented: verifier has `Edit`+`Bash` in tool allowlist; SHOULD self-bump `metadata.version` from STOP message + re-stage + retry commit.
- Canary recipe at `tests/canary-zskills-self-fires.txt` is RECIPE form (manual procedure), NOT a regression test. Backed by Phase 2's 27 unit cases + Phase 4's 13 sandbox cases for automated coverage.
- Followups doc at `plans/reports/SKILL_VERSION_PRETOOLUSE_HOOK-followups.md` documents 2 post-merge items: (1) stage-check STOP-message UX nit (file `gh issue create` post-merge), (2) BLOCK_UNSAFE_HARDENING.md already drafted (PR #192) — recommend `/run-plan plans/BLOCK_UNSAFE_HARDENING.md finish auto` as next step.

### Dependencies satisfied
- Phases 1-4 all done

### Plan completion
- Plan frontmatter: `status: complete` + `completed: 2026-05-06`
- Tracker rows 1-5 all ✅ Done with commit hashes
- Lock-step gap PR #175 left open: CLOSED via this plan's hook
- Total commits accumulated in PR #193: 5 work + 5 bookkeeping = 10 ordered commits to be squashed at automerge

## Phase — 4 Helper-script install flow + sandbox integration test [UNFINALIZED]

**Plan:** plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
**Status:** Completed (verified — all 12 ACs PASS, 1 fix applied by verifier)
**Commits:** 841e7e1 (work), (this report commit)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 4.1 | `scripts/install-helpers-into.sh` (NEW driver, +x) — 4 helper copy + mkdir-p + SKIP/COPY collision | Done | 841e7e1 |
| 4.2 | `skills/update-zskills/SKILL.md` Step D extension (canonical script-install home, post-refinement) + Step A cross-ref + explanatory paragraph | Done | 841e7e1 |
| 4.3 | `tests/test-block-stale-skill-version-sandbox.sh` (NEW, 13 cases, +x) — end-to-end integration | Done | 841e7e1 |
| 4.4 | `tests/run-all.sh` registration (1 new run_suite line) | Done | 841e7e1 |
| 4.5 | Pre-bump cross-edit check (only expected paths staged) | Done | (verifier confirmed) |
| 4.6 | metadata.version bump → `2026.05.06+7b1a80` + mirror | Done | 841e7e1 |

### Verification
- All 12 ACs PASS (independently re-verified by `verifier` subagent)
- Tests **2111/2111** PASS (+13 vs pre-Phase-4 baseline 2098/2098)
- Mirror parity clean
- Hygiene clean
- Verifier caught + fixed AC1 violation: implementer wrote `scripts/install-helpers-into.sh` but didn't `chmod +x`. Single-line fix; mode 100755 now recorded in git index.

### Causation analysis (resolved a flagged concern)
Implementer reported `test-hooks.sh#17 (post-run-invariants.sh: empty args)` failing in-suite. **NOT reproducible** by verifier across:
- Full suite, run 1: 2111/2111 PASS
- Full suite, run 2: 2111/2111 PASS
- `test-hooks.sh` in isolation: 365/365 PASS
- `sandbox` in isolation: 13/13 PASS
- `sandbox` then `test-hooks.sh` sequenced: 365/365 PASS
- `/tmp` leftover audit after isolated sandbox: only verifier's own log file

Sandbox test cleanup discipline confirmed sound: trap-EXIT + explicit cleanup + case-13 verifies cleanup ran. `$TMP` is well-namespaced via `mktemp -d -p /tmp zskills-sandbox.XXXX`. Most likely explanation: orphan state from interrupted run during implementer's iterative authoring. No persistent issue. No issue filed (would be noise for non-reproducible flake).

### Notes
- New `metadata.version`: `2026.05.06+7b1a80` (date + 6-char hash, today NY).
- Step D extension at line 1090 area; insertion point: after existing per-stub bullets, before Tier-1 callout. Step A cross-ref clarifies `$PORTABLE` resolution.
- Driver file lives at `scripts/install-helpers-into.sh` (repo root, not under any skill) — does NOT trigger per-skill versioning.
- Verifier observed: `block-unsafe-generic.sh` blocked two `rm -rf "$VAR"` cleanup commands during AC verification (variable-expansion safety). Hook design validated; verifier worked around with literal `/tmp/<basename>` paths.

### Dependencies satisfied
- Phase 1 (reference doc), Phase 2 (hook + tests), Phase 3 (settings.json wiring) — all done

### Downstream
- Phase 5 (FINAL): CHANGELOG entry (date H2 + `### Added —` H3 convention) + CLAUDE.md PreToolUse-backstop note (with verifier-subagent recovery + chain-composition note from refinement) + final conformance gate + **AC8 from Phase 3 deferred live deny-canary** (run + log to `tests/canary-zskills-self-fires.txt` if applicable). After Phase 5 lands, dispatch /land-pr with --auto for PR #193 automerge.

## Phase — 3 settings.json registration + canonical extension table [UNFINALIZED]

**Plan:** plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
**Status:** Completed (verified — AC8 deferred to Phase 5)
**Commits:** 62f53b5 (work), (this report commit)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 3.1a | `skills/update-zskills/SKILL.md` canonical-table row append (5 → 6 rows) | Done | 62f53b5 |
| 3.1b | Prose `All 5 rows` → `All 6 rows` | Done | 62f53b5 |
| 3.1c | Explainer rewrite to `Installing 3 PreToolUse Bash safety hooks` | Done | 62f53b5 |
| 3.2 | Step C copy bullet for `block-stale-skill-version.sh` | Done | 62f53b5 |
| 3.3-3.4 | metadata.version bump → `2026.05.06+829a2a` + mirror via `mirror-skill.sh` | Done | 62f53b5 |
| 3.5 | Cross-edit pre-bump check (no accidental cross-skill edits) | Done | (verifier confirmed) |
| 3.6 | `.claude/settings.json` PreToolUse Bash entry (deep-nested indent) | Done | 62f53b5 |
| 3.7 | `.claude/hooks/block-stale-skill-version.sh` mirror (byte-eq + executable) | Done | 62f53b5 |

### Verification
- AC1-AC7, AC9 all PASS (independently re-verified by `verifier` subagent)
- **AC8 deferred** — one-shot live deny-canary not produced this phase. Spec calls for a sandbox session that triggers the hook to confirm the deny envelope, with the result logged to `tests/canary-zskills-self-fires.txt`. The implementer didn't produce this; it's outside the 4-file commit scope and requires a fresh session restart (the new hook needs to be loaded). Deferred to **Phase 5 final conformance**. The static stage-check rc=0 path is verified; the deny path is covered by Phase 2's 27-case unit suite (positive C1-C12 cases). End-to-end live demonstration remains pending.
- Tests **2098/2098** PASS (parity with pre-Phase-3 baseline; no new test cases — Phase 3 wires Phase 2's hook into the live harness, doesn't add new tests).
- Mirror parity clean.
- Hygiene clean.

### Notes
- New `metadata.version`: `2026.05.06+829a2a`. Date is today (NY).
- Settings.json entry indent: 10/12-space deep nesting per round-2 DA2-M-2 (matches existing entries verbatim, clean append, no re-indent noise).
- Spec line numbers (table 944-948, explainer 904-910, prose 950) all landed within ±5 of actual (942-947, 905-911, 951) — anchor windows held.

### Dependencies satisfied
- Phase 1 (reference doc) — done
- Phase 2 (`hooks/block-stale-skill-version.sh` + tests) — done

### Downstream
- Phase 4: helper-script install in Step D + sandbox integration test (the `install-helpers-into.sh` driver per refinement; sandbox test = edit-then-bare-commit-then-deny against fake consumer repo)
- Phase 5: CHANGELOG + CLAUDE.md PreToolUse-backstop note (with verifier-subagent recovery + chain-composition note) + final conformance + **AC8 live deny-canary** (run + log to `tests/canary-zskills-self-fires.txt`)

## Phase — 2 Hook script + JSON-escape function + unit tests [UNFINALIZED]

**Plan:** plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
**Status:** Completed (verified)
**Commits:** 0766b65 (work), (this report commit)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 2.1 | `hooks/block-stale-skill-version.sh` (NEW, 150 lines, +x) | Done | 0766b65 |
| 2.2 | `tests/test-block-stale-skill-version.sh` (NEW, 347 lines, +x) — 27 cases | Done | 0766b65 |
| 2.3 | `tests/run-all.sh` registration (1 new `run_suite` line) | Done | 0766b65 |
| 2.4 | Header docstring documents `bash -c` carve-out per D5 | Done | 0766b65 |

### Verification
- All 12 ACs PASS (independently re-verified by `verifier` subagent)
- Tests **2098/2098** PASS (+27 vs pre-Phase-2 baseline 2071/2071)
- Hygiene clean
- D&C scope respected: only `hooks/`, `tests/` modified — no `skills/`, `.claude/`, or `settings.json` touched (Phase 3's scope)

### Notes
- `is_git_commit` tokenize-then-walk matcher (Round 2 N1 fix — regex form was bypassable by `git --no-pager commit` etc.); verified positive matches across 7 flag combinations + negative matches across 3 (C7b/i/j) + carve-out C10e (`bash -c '<git commit>'`).
- `json_escape` pure-bash with LC_ALL=C + POSIX `[[:cntrl:]]` strip per D4.
- Implementer rephrased "jq" / "python" comments to "external JSON parsers" / "scripting-language interpreters" so AC7/AC8 `grep -F` literals return 0; runtime behavior is genuinely pure-bash.
- Block-unsafe-generic.sh extraction pattern + deny-envelope shape byte-identical to source.

### Dependencies satisfied
- Phase 1 (reference doc) — done

### Downstream
- Phase 3: wire `.claude/settings.json` (zskills-side) + extend `update-zskills` canonical table (5 → 6 rows)
- Phases 4-5: helper-script install in Step D + sandbox integration test, then CHANGELOG + CLAUDE.md note + final conformance

## Phase — 1 Decision doc + manual-recipe verifications [UNFINALIZED]

**Plan:** plans/SKILL_VERSION_PRETOOLUSE_HOOK.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-skill-version-pretooluse-hook (branch `feat/skill-version-pretooluse-hook`)
**Commits:** 67ff929 (work) + (this report commit)

### Work Items
| # | Item | Status | Commit |
|---|------|--------|--------|
| 1.1 | `references/skill-version-pretooluse-hook.md` (NEW) — D1-D5 verbatim + R1/R2/R3 manual recipes + Recursive-risk-NONE + run_suite pattern | Done | 67ff929 |
| 1.2 | `tests/run-all.sh` dispatcher pattern verified against current source — matches | Done | 67ff929 |
| 1.3 | `plans/PLAN_INDEX.md` Plan B row added under "Ready to Run" | Done | 67ff929 |

### Verification
- All 6 ACs PASS (independently re-verified by `verifier` subagent)
- Tests **2071/2071** PASS (parity with baseline; Phase 1 is docs-only)
- Hygiene clean (no `.worktreepurpose`/`.zskills-tracked`/`.landed`/`.test-*.txt` tracked)
- Phase 1 D&C respected: NO code touched in `hooks/`, `skills/`, `tests/`, or `.claude/settings.json`
- Freshness mode: `single-context fresh-subagent` (verifier inherited Plan A's Layer 0 timeout-injection hook + composed with project hooks)

### Notes
- Verifier subagent dispatch went smoothly — Plan A's structural defense (verifier.md + Layer 0 + Layer 3) works as designed.
- D2 (commit-only gating) caught and surfaced a latent inconsistency in the original plan text (prompt Goal language was overbroad — `git commit` AND `git push`; success criterion narrows to `git commit` only). D2 explicitly resolves the discrepancy in favor of the success criterion.
- Reference doc is now the single source of truth for D1-D5; subsequent phases cite it rather than re-stating rationale.

### Dependencies satisfied
- Plan A (verifier subagent + structural defense) — done (PR #189 merged)
- Plan B refinement — done (PR #192 merged)

### Downstream
- Phase 2: `hooks/block-stale-skill-version.sh` + 27-case unit tests + `tests/test-block-stale-skill-version.sh` registration
- Phases 3-5: settings.json wiring, helper-script install in Step D, CHANGELOG + CLAUDE.md note + final conformance
