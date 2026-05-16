---
title: Issues — General Tracker
status: active
created: 2026-05-15
last_sync: 2026-05-15
---

# Issues — General Tracker

Created by `/fix-issues sync` on 2026-05-15 for issues not covered by domain-specific trackers (QE_ISSUES.md, etc). Each entry: problem + suggested fix + complexity tier.

## Open Issues

### #67 — GitLab (glab) support — deferred until prerequisite plans land

**Labels:** enhancement | **Verdict:** NOT FIXED — author-deferred

**Problem.** ~100+ \`gh\` invocations across 16+ skill files assume GitHub. Consumer on GitLab cannot use zskills as-is.

**Status.** Issue body explicitly defers: "not ready to start yet." Three prereq plans are gating: SCRIPTS_INTO_SKILLS, SKILL_FILE_DRIFT_FIX, CONSUMER_STUB_CALLOUTS. Plus an external prereq (a real GitLab project to test against) is missing.

**Fix outline.** When prereqs land: single host-CLI shim (gh ↔ glab abstraction); not per-skill switching. Full parity at user-visible surface (auto-merge, CI poll, JSON parsing, draft MRs). Planning prompts already drafted at \`plans/GITLAB_SUPPORT_DRAFT_PLAN_PROMPTS.md\`.

**Complexity:** L (multi-plan effort when started). **Action now:** none — leave open as architectural memo.

---

### #217 — Relocate plan execution reports out of \`.zskills/audit/\` (work-trail vs forensic separation)

**Labels:** (none) | **Verdict:** NOT FIXED — author-deferred ("not immediately")

**Problem.** PR #211's path-config refactor framed \`.zskills/audit/\` as gitignored forensic exhaust, but per-plan execution reports written by \`/run-plan\` Phase 5 to \`.zskills/audit/plan-{slug}.md\` are work-trail documentation, not forensic state. Currently 52 historical reports are tracked under audit/ despite the dir being gitignored — hybrid status.

**Fix outline.** Add \`$ZSKILLS_REPORTS_DIR\` config field (or hardcode \`docs/plans/reports/\`); update writers (/run-plan Phase 5, /fix-report, /briefing); update readers (/fix-report Step 2 sign-off scan); migrate existing tracked reports; cross-ref rewrite for plan files referencing old paths; conformance fixture updates.

**Complexity:** L (200-300 LOC + 3-4 phases per author estimate). **Trigger to act:** consumer trips on hybrid tracking inconsistency, OR next minor-release scoping. **Action now:** none — leave open as architectural memo.

---

### #278 — \`/research-and-go\` pipeline abandoned after user interrupt + permissions fix

**Labels:** bug | **Verdict:** NOT FIXED — split into 4 sub-fixes

**Problem.** Pipeline ran Step 0 (tracking setup) but never reached Step 1 (\`/research-and-plan\` invocation). Agent dispatched research sub-agents instead of the formal skill, got interrupted by user for permissions issues, never recovered. Compaction at 15:06 wiped remaining context. Post-compaction agent built features ad-hoc with no plan, no adversarial review, leaving orphaned tracking state.

**Fix outline (4 sub-fixes):**
- **Fix #1 — atomic Step 0+1** (S, /quickfix): single-file prose edit to \`skills/research-and-go/SKILL.md:55-177\` so the same response that ends Step 0 bash issues the \`/research-and-plan\` Skill call.
- **Fix #2 — compaction-resilience PreCompact hook** (L, /draft-plan): no PreCompact hook precedent in repo; new hook event + cross-skill semantics + verification injected text survives compaction.
- **Fix #3 — SessionStart orphaned-pipeline detector** (M, /draft-plan): no SessionStart hook precedent; needs design for stalled threshold, surface format, intentional-resume interaction.
- **Fix #4 — step.* markers** (no-op): already exists per \`docs/tracking/TRACKING_NAMING.md:413-415\`, used by \`/run-plan\`. Bundle thin prose addition into Fix #1.

**Complexity:** Mixed. **Action now:** Fix #1 + #4 prose roll-in (combined /quickfix S). Fix #2 + #3 deferred to /draft-plan when prioritized.

---

### #288 — \`ZSKILLS_PYTHON\` env override (handle python3-vs-python on Windows / non-standard distros)

**Labels:** (none) | **Verdict:** NOT FIXED — scope correction in comment

**Problem.** zskills hardcodes \`python3\` in several places. Windows and some Linux distros only have \`python\` (pointing at Python 3). Currently fails.

**Investigated correction (in issue comment).** Issue body claims "~15 call sites" but verified grep shows only 1 prod \`.sh\` invokes python3 (\`hooks/inject-bash-timeout.sh:51\`). The 19 tests/*.sh hits are bash-internal helpers, not framework runtime. Python files have shebangs (separate channel from bash invocation; keep).

**Fix outline.** Trim scope to: (a) \`ZSKILLS_PYTHON\` envvar in the hook with cheap precedence (\`PYTHON=\${ZSKILLS_PYTHON:-\$(command -v python3 || command -v python)}\`); (b) document Python policy in CLAUDE.md / CLAUDE_TEMPLATE.md. SKIP the PYTHON_CMD helper refactor + sed sweep described in body — would add dead plumbing.

**Complexity:** S (~1h, fix-agent or /quickfix). **Action now:** include in next sprint.

---

### #289 — Drop \`briefing.cjs\` — rejoin the briefing fork (briefing.py wins)

**Labels:** (none) | **Verdict:** NOT FIXED — scope EXPANSION in comment

**Problem.** \`skills/briefing/scripts/\` has both briefing.cjs (1945 lines node) AND briefing.py (1716 lines python), maintained in lockstep via parity tests. The portability promise was implicitly broken when zskills_monitor (PR #111) shipped Python-only; subsequent additions (inject-bash-timeout.sh, render-index.py) compounded. Briefing's dual-impl is now a lone artifact of a dead policy.

**Investigated correction (in issue comment).** Body's plan understates blast radius — verified ~12 additional consumer refs need coordinated edits in same PR: \`skills/update-zskills/SKILL.md:681,743,758,761,806,1402,1623\`; \`references/script-ownership.md:27,63,133\`; \`references/stub-callouts.md:78\`; \`tests/test-update-zskills-migration.sh:88\` (asserts briefing.cjs presence; will fail unless updated lockstep); doc-comment refs in \`zskills_monitor/{server.py:237, collect.py:219}\`; self-refs in \`briefing.py:6,19,52\`.

**Fix outline.** Delete briefing.cjs source + mirror; edit briefing/SKILL.md fallback prose; drop parity-test sections in test-briefing-parity.sh (KEEP smoke tests); update all 12 consumer refs in lockstep; bump version + mirror.

**Complexity:** M (2-3h, /quickfix — plan-review valuable for enumeration). **Action now:** include in next sprint.

---

### #291 — CLAUDE_TEMPLATE.md: add skill-routing decision table

**Labels:** (none) | **Verdict:** NOT FIXED — trivial

**Problem.** Agents in zskills and downstream consumers derive skill-routing decisions from individual skill descriptions or session memory. A central lookup table in CLAUDE_TEMPLATE.md would distribute the model.

**Fix outline.** Add a "Which skill for which input" section to CLAUDE_TEMPLATE.md with a routing table (clear bug → /quickfix; backlog of bugs → /fix-issues N; bug + unknown cause → /investigate; plan ready → /run-plan; plan-scale → /draft-plan; small ad-hoc task → /do). Auto-propagates to consumers via \`/update-zskills\` Step B.

**Complexity:** S (~30min, fix-agent). Single-file edit to CLAUDE_TEMPLATE.md, no skill version bumps (CLAUDE_TEMPLATE.md isn't a skill), trivial /update-zskills round-trip check. **Action now:** include in next sprint.

---

### #293 — \`/quickfix\`: drop PR-only constraint; support worktree/direct landing modes

**Labels:** (none) | **Verdict:** NOT FIXED — Approach A only

**Problem.** \`/quickfix\` currently emits hard error and exits when \`execution.landing != "pr"\` (skills/quickfix/SKILL.md:187-191). Per PR #290 review, this drifts from the project principle "all skills should work in all landing modes." 49 references to PR scaffolding in /quickfix's body confirm Phases 6+7 are PR-shaped.

**Investigated correction.** Approach A in body proposes folding into #292's "new Phase 0a" — but #292 was incorrectly filed (already implemented as WI 1.5.4) and was closed. Approach A pivots to: replace the hard error at SKILL.md:187-191 with a soft redirect message (using same two-line redirect template /quickfix already uses elsewhere). 5-line edit at the same code position — same layer, no Phase-0a entanglement.

**Fix outline (Approach A — small).** Replace lines 187-191's hard error with redirect: worktree mode → "/do worktree" suggestion + exit 0; direct mode → "/commit" suggestion + exit 0. Use the existing two-line redirect printf template.

**Approach B (heavy, deferred).** Native multi-mode rework of Phases 6+7. Plan-scale. /draft-plan when consumers actually want native multi-mode (speculative).

**Complexity:** S (~15min, fix-agent). **Action now:** include in next sprint.

---

### #295 — \`/fix-issues\`: 3-worktree cap addresses only 9p checkout contention, not aggregate live-worktree load

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session

**Problem.** \`/fix-issues\` Phase 3 caps simultaneous worktree-agent dispatches at 3 per message. Justification cited in spec: 9p-filesystem checkout contention. The cap controls **simultaneous \`git checkout\` operations during dispatch**, NOT the number of worktrees alive concurrently. For \`/fix-issues 8\`, dispatch staggers into batches of 3+3+2, but each worktree stays live until PR lands — by mid-sprint, all 8 are concurrently active running tests + verifiers + CI.

**Fix outline.** Add \`execution.max_concurrent_worktrees\` to \`.claude/zskills-config.json\` (default 3). Throttle Phase 3 spawns based on live-worktree count (defined as: worktree dir exists + \`.landed\` marker absent — observable from filesystem, no event tracking). Per-skill option vs hardcode default — design call.

**Complexity:** M (~2-4h, /quickfix). 4-5 acceptance items at the auto-REVISE threshold; /quickfix's plan-review will surface design decisions if needed. **Action now:** include in next sprint.

---

### #297 — \`/do\` should support positional \`auto\` token (parity with /quickfix PR #260)

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session

**Problem.** \`/do pr\` is one of 5 PR-landing callers but doesn't parse positional \`auto\`. Token falls through and ends up in TASK_DESCRIPTION as user prose. \`skills/do/modes/pr.md:174,303\` hardcode comments saying auto-merge stays OFF. Caused this session: \`/do <task> auto pr\` produced PR requiring manual merge despite \`auto\` intent — manual \`gh pr merge --auto\` workaround.

**Root cause.** \`auto\` parsing landed in \`/quickfix\` via PR #260 (\`closes #235, #241\`); parallel update never applied to \`/do\`.

**Fix outline (smallest).** Mirror /quickfix's pattern in \`skills/do/SKILL.md\`: add \`auto\` to trailing-flag pre-parse (case-insensitive positional token), set \`AUTO_FLAG=1\`, strip from TASK_DESCRIPTION, pass \`--auto\` into \`/land-pr\` invocation in \`modes/pr.md\` when AUTO_FLAG=1. Update the two stale comments.

**Complexity:** S (~30min, fix-agent or /quickfix). Verify whether /run-plan + /fix-issues PR mode also lag — if yes, batch all 4 callers; if no, /do alone. **Action now:** include in next sprint.

---

### #300 — \`/fix-issues\` sync: TRACKING_ID / PIPELINE_ID naming mismatch breaks Step 8b fulfilled-marker writes

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session

**Problem.** Sync mode passes \`--tracking-id=$SYNC_ID\` to \`/land-pr\` but never exports \`ZSKILLS_PIPELINE_ID\`. Inside \`/land-pr\` Step 8b, \`PIPELINE_ID\` falls back to \`run-plan.$TRACKING_ID\` (= \`run-plan.fix-issues.sync.$TS\`), which never matches the actual subdir \`fix-issues.$TS\`. Result: \`fulfilled.land-pr.*\` marker silently never written; \`requires.*\` marker remains unsatisfied. Hit 2026-05-16 PR #299 — required manual reconciliation.

**Fix outline.** In \`skills/fix-issues/SKILL.md\` sync mode Step 5 sub-step 2, add \`export ZSKILLS_PIPELINE_ID="$PIPELINE_ID"\` immediately before the \`/land-pr\` Skill dispatch. Mirrors \`/run-plan\` and \`/do pr\` convention (they echo the same for transcript propagation).

**Complexity:** S (single-line addition + version bump + mirror; fix-agent). **Action now:** include in next sprint.

---

### #301 — \`/fix-issues\` sync: gap-detection regex \`[^0-9A-Za-z_]\` doesn't match \`**#NNN**\` markdown bold

**Labels:** (none) | **Verdict:** NOT FIXED — filed this session; reproduced again 2026-05-16

**Problem.** Sync's gap-detection grep \`(^|[^0-9A-Za-z_])#$N($|[^0-9])\` fails to match issue references in markdown bold (\`**#279**\`) or heading positions (\`### #288 — ...\`) due to a grep ERE alternation quirk with the inner character class. Net effect: every sync incorrectly marks already-tracked issues as gaps, then the row-writer duplicates them into \`ISSUES_PLAN.md\`. Confirmed reproducible: \`grep -E '(^|[^0-9A-Za-z_])#288($|[^0-9])'\` returns no match against the literal heading line.

**Fix outline.** Switch the two grep sites in \`skills/fix-issues/SKILL.md\` (Phase 1 sync row-writer membership check + the gap-listing while-loop) from \`grep -qE\` with the alternation regex to \`grep -qP "(?<![0-9])#$N(?![0-9])"\` (PCRE lookarounds, supported by GNU grep on the project's standard environment). Add a fixture exercising both \`**#NNN**\` and \`### #NNN\` formatting.

**Complexity:** S (two regex sites + version bump + mirror + fixture; fix-agent). **Action now:** include in next sprint.

---

