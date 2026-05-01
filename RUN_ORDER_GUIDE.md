# PR #70 Batch — Execution Order Guide

This is the recommended order for running every plan, queued `/quickfix`, and open issue committed in [PR #70](https://github.com/zeveck/zskills-dev/pull/70) plus issues [#56](https://github.com/zeveck/zskills-dev/issues/56), [#58](https://github.com/zeveck/zskills-dev/issues/58), and [#65](https://github.com/zeveck/zskills-dev/issues/65).

Order matters because several items churn the same files (`skills/update-zskills/SKILL.md`, `dev_server.default_port` schema, the `update-zskills` mirror). Two `/refine-plan` reconciliations are required mid-stream — the rest reduces to staleness gates inside the plans themselves.

---

## Drift log

- **2026-04-27 (early)** — Issue #58 (`main_protected` push-guard regex false-positive) was already closed by [PR #73](https://github.com/zeveck/zskills-dev/pull/73) merged the same day this guide was written. The fix segment-scopes rules (a) and (b) to the `git push` portion of `$COMMAND` (`hooks/block-unsafe-project.sh.template:639-655`) and adds 9 regression tests in `tests/test-hooks.sh`. **Step removed from Phase A**; subsequent steps renumbered.
- **2026-04-27 (mid)** — Issue #56 closed by [PR #74](https://github.com/zeveck/zskills-dev/pull/74) merged. Phase A item 1 marked complete.
- **2026-04-27 (late)** — A drift across 5 PR-creating skills (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`) was surfaced during the `/fix-issues 56 + 58` sprint: each skill duplicates the canonical `gh pr create` + CI poll + fix cycle + auto-merge pattern, with inconsistent gating and one skill (`/quickfix`) opting out entirely. [PR #75](https://github.com/zeveck/zskills-dev/pull/75) (merged 2026-04-27 22:51, commit `82ee65f`) fixes the `/fix-issues` half — interactive PR-mode now runs the full pipeline except the final `gh pr merge`, matching `/run-plan`, `/commit pr`, and `/do pr`. The broader unification was explicitly deferred by PR #75 as out-of-scope ("future `/draft-plan` candidate").
- **2026-04-27 (later)** — `plans/PR_LANDING_UNIFICATION.md` drafted on branch `plans/pr-landing-unification` (worktree `/tmp/zskills-worktrees/pr-landing-unification`). 912 lines, 7 phases (1A foundation → 1B validation → 2 `/run-plan` → 3 `/commit pr`+`/do pr` → 4 `/fix-issues pr` → 5 `/quickfix` → 6 conformance), produced via `/draft-plan rounds 3` + `/refine-plan` YAGNI pass. Creates a new `/land-pr` skill that the 5 callers dispatch via the Skill tool. Branch is based on `47e8344` (pre-PR #75); needs rebase onto main before landing. Phase F entry below moves from "needs draft" to "needs merge".
- **2026-04-28** — Session-of-2026-04-28 PRs merged: PR #76 (no-Haiku CLAUDE.md rule), PR #77 (PR_LANDING_UNIFICATION plan onto main → executable now), PR #78 (QUEUED_QUICKFIXES QF2 + QF4 revised per Opus re-review — when you run those quickfixes, copy from the revised file), PR #79 (QF1 done), PR #80 (`/quickfix` now returns user to base branch on success — fixes a session-friction gap that surfaced during the QF1 run). [Issue #81](https://github.com/zeveck/zskills-dev/issues/81) filed: `main_protected` push-guard rule (c) false-positives on literal `git push` substrings (e.g. inside grep args) — non-blocking but worth picking up alongside the QF2/QF4 runs.
- **2026-04-28 (late)** — Session-end status: Phase A pre-flight is **fully complete**. PR #82 (QF2 — orchestrator-judgment convergence fix), PR #85 (QF4 — `/refine-plan` positional-tail guidance + spaces fix), PR #86 (Issue #83 — `/research-and-plan` Step 3 orchestrator-judgment), PR #87 (Issue #81 — push-guard rule (c) + outer-regex EOL fix), PR #88 (Issue #84 — `scripts/mirror-skill.sh` helper). Three new follow-up issues filed and resolved in-session: Issue #83 (closed by PR #86), Issue #84 (closed by PR #88). Issue #81 closed by PR #87. **Open issues remaining: #65 (block-diagram tracking — addressed by `BLOCK_DIAGRAM_TRACKING_CATCHUP.md` plan in Phase F) and #67 (GitLab support — explicitly deferred).** **/refine-plan triggers added inline** to Phase D and Phase F entries (previously missing from the execution checklist; pre-run hygiene to absorb drift from prior-phase landings).
- **2026-04-28 (later)** — `IMPROVE_STALENESS_DETECTION.md` landed via chunked `finish auto` PR mode: PR #90 (Phase 1: `PLAN-TEXT-DRIFT:` token + `scripts/plan-drift-correct.sh`, 34 cases), PR #91 (Phase 2: `## Phase 3.5` post-implement auto-correct gate, +5 cases), PR #92 (Phase 3: pre-dispatch arithmetic gate sub-checks `a`/`b` + `--eval` token-walking parser with injection canary, +29 cases). Plan frontmatter `status: complete`. 863 → 931 tests passing (+68 plan-drift cases total). The defense-in-depth chain is now complete: `/refine-plan` Dimension 7 (pre-authoring) + Phase 1 step 6 b (pre-dispatch) + Phase 3.5 (post-implement). All 3 layers share the `PLAN-TEXT-DRIFT:` vocabulary and the `plan-drift-correct.sh` helper. Phase A of ROG: every item now `[x]`.
- **2026-04-28 (latest)** — `SCRIPTS_INTO_SKILLS_PLAN.md` (Phase B foundation) landed via chunked `finish auto` PR mode after `/refine-plan` (PR #94 absorbed since-draft drift: `mirror-skill.sh` + `plan-drift-correct.sh` registry entries, hook-blocked `rm -rf .claude/skills/X` recipes replaced with `bash scripts/mirror-skill.sh`, `git rev-parse <commit>:<wildcard-path>` rewrite). Then 6 PRs: #95 (Phase 1: dead-ref cleanup + `script-ownership.md` registry, 14 Tier-1 + 4 Tier-2), #96 (Phase 2: 7 single-owner Tier-1 scripts moved into owning skills), #97 (Phase 3a+3b combined: 7 shared Tier-1 scripts moved + cross-skill caller sweep across 13 skills + hooks + 6 tests + docs + port.sh PROJECT_ROOT bug fix + DEFAULT_PORT_CONFIG Phase 1 inline schema/this-repo-config/template), #98 (Phase 4: `/update-zskills` Step D rewrite + Step D.5 stale-Tier-1 migration via 26-hash known-shipped fixture + CRLF-normalizing hash compare + `command -v git` pre-flight + `port_script` strip; +12 migration tests), #99 (Phase 5: residual sweep + `port_script` schema field removal), #100 (Phase 6: CHANGELOG + RELEASING.md migration note + PLAN_INDEX move + frontmatter flip). Plan frontmatter `status: complete; completed: 2026-04-28`. 931 → 943 tests. **Phase B of ROG complete; DEFAULT_PORT_CONFIG Phase 1 was reconciled inline and is no longer needed as a separate plan**. ROG Phase C's `/refine-plan plans/DEFAULT_PORT_CONFIG.md` step still applies — refine should detect the inline-landed work and strip those WIs.
- **2026-04-29 (later)** — `SKILL_FILE_DRIFT_FIX.md` landed via PR-mode chunked `finish auto`. Refine via PR #121 (2 rounds; 35+36 findings; refine-2 reframed away `__SNAKE__`/sed mechanism in favor of existing model-side `$VAR` substitution discipline at `skills/run-plan/SKILL.md:181`). Then 5 phases on `feat/skill-file-drift-fix` accumulated to PR #122 (squash `f11c67e`): Phase 0 staleness gate (inline preflight), Phase 1 helper script `zskills-resolve-config.sh` + `references/canonical-config-prelude.md` (+24 tests), Phase 2 migration of ~97 hardcoded references across 50 files (+12 tests; INJECTED-BLOCKQUOTE migrated via model-side discipline), Phase 3 hook fallback fix + test-infra detection sync (+9 tests; three-case tree), Phase 4 enforcement: deny-list + drift-warn hook + allowlist convention (+10 tests; 4-entry shared fixture), Phase 5 verification + drift-regression test (+4 tests; positive-side fence-local check surfaced 3 Phase-2 misses, all fixed). Tests 1213→1272 (+59 across plan). Plan frontmatter `status:complete; completed:2026-04-29`. **Phase D of ROG complete**.
- **2026-04-30** — `DEFAULT_PORT_CONFIG.md` landed via PR-mode chunked `finish auto` (PR #125, `da108b4`). Refine via PR #119 (2026-04-28) absorbed Phase B inline-landings (WIs 1.1–1.3) and added Phase P1.A (CHANGELOG correction + greenfield template port_script remnant). Then 5 phases on `feat/default-port-config` accumulated to PR #125: Phase 2 port.sh tightening (regex `[^}]*`→`[^{}]*`, fail-loud guard scoped to main-repo branch, PROJECT_ROOT env override, +3 fixture cases), Phase P1.A CHANGELOG + greenfield template strip, Phase 3 `{{DEFAULT_PORT}}` + `{{MAIN_REPO_PATH}}` substitution mapping (active shipping bug for `{{MAIN_REPO_PATH}}`; conformance test reconciled against SKILL_FILE_DRIFT_FIX assertions; +6 cases), Phase 4 briefing.{py,cjs} path-fix + drop 8080 fallback + omit URL on failure (path drifted when SCRIPTS_INTO_SKILLS relocated port.sh; +5 parity cases), Phase 5 docs sweep (briefing/SKILL.md `<port>` + manual-testing/SKILL.md prose). Tier-1 hash discipline: `tier1-shipped-hashes.txt` updated with new port.sh, briefing.py, briefing.cjs blob hashes. CI green in 54s; auto-merge on green. Tests 1213→1347 (+14 own across the run; +121 from concurrent SKILL_FILE_DRIFT_FIX/DRAFT_TESTS_SKILL_PLAN merges absorbed via inter-phase rebases). Plan frontmatter `status: complete; completed: 2026-04-29`. **Phase C of ROG complete; Phase E now unblocked.** One spec deviation: `tests/test-skill-conformance.sh` reconciled against SKILL_FILE_DRIFT_FIX (#122)'s pre-Phase-3 assumptions (post-reconciliation assertion is stricter, not weaker — verified). Auto-backfill of `default_port` into existing configs explicitly deferred to future-work in CHANGELOG.
- **2026-04-29** — `ZSKILLS_MONITOR_PLAN.md` landed via PR-mode chunked `finish auto`. Refine via PR #101 (2026-04-28; +685/-247 absorbing post-PR-#100 SCRIPTS_INTO_SKILLS drift). Then 9 phase PRs: #102 (Phase 1: `/work-on-plans` execute-only CLI, 943→943 + new skill 677 lines), #104 (Phase 2: retire `/plans work` modes), #107 (Phase 3: queue mutation + scheduling subcommands; SKILL 677→1249, +28 tests), #108 (Phase 4: 1277-line `collect.py` data aggregator; +29 tests), #111 (Phase 5: HTTP server with security contract; +53 tests), #113 (Phase 6: read-only dashboard UI; +45 tests, 1111/1111), #115 (Phase 7: drag-drop + write-back; +47 tests, 1158/1158), #116 (Phase 8: `/zskills-dashboard` skill with cmd+cwd identity check; +35 tests, 1193/1193), #117 (Phase 9: `/plans rebuild` migrated to Python aggregator, no bash fallback; +20 tests, 1213/1213). PR #118 marks plan complete. **Phase F's ZSKILLS_MONITOR_PLAN entry is done; new `/work-on-plans` and `/zskills-dashboard` skills shipped.** Two parallel sessions during this stretch landed `BLOCK_DIAGRAM_TRACKING_CATCHUP.md` (PR #109) and `CONSUMER_STUB_CALLOUTS_PLAN.md` (PR #106).
- **2026-04-29 (sprint)** — `/fix-issues 123 126 93 89 110` sprint via interactive PR mode (5 issues triaged: 4 clear-and-doable, 1 too-complex deferred to `/draft-plan`). Landed in 4 parallel PRs: [#127](https://github.com/zeveck/zskills-dev/pull/127) (issue #123 — `tests/test_plans_rebuild_uses_collect.sh` truncating `$TEST_OUT/.test-results.txt`; renamed RESULTS to per-test scratch path), [#128](https://github.com/zeveck/zskills-dev/pull/128) (issue #126 / QF3 — `/update-zskills` extended source-asset probe + stop-and-ask replacing silent auto-clone; merged 2026-04-30T04:23Z), [#129](https://github.com/zeveck/zskills-dev/pull/129) (issue #93 — hook `extract_cd_target` multi-line bash JSON `\n` decoding; +3 regression tests via real JSON envelopes), [#130](https://github.com/zeveck/zskills-dev/pull/130) (issue #89 — `mirror-skill.sh` orphan-dir test gap; +2 cases, break-and-revert proof). Issue #110 was triaged as too-complex (multi-mode unified design with 6 untested architectural questions) and deferred to `/draft-plan` via `/fix-issues plan` mode. **Notable mid-sprint**: 5/5 sub-agent dispatch crashes (consistent "let me wait for the monitor" hallucination) — root cause unknown after this-session investigation; user observation suggests API-side rate-limit truncation; agent IDs preserved for upstream report. Skill-prose-skip enforcement gap surfaced as [Issue #133](https://github.com/zeveck/zskills-dev/issues/133) — `/commit pr` Step 6 CI poll was skipped during PR #131's landing, which masked the next ROG-relevant landing's CI flake.

- **2026-04-30** — Bookkeeping [PR #131](https://github.com/zeveck/zskills-dev/pull/131) (`docs(plans,sprint): add ADAPTIVE_CRON_BACKOFF plan + 2026-04-29 sprint record`) merged. Captures `plans/ADAPTIVE_CRON_BACKOFF.md` (1199 lines; `/draft-plan` 2 rounds adversarial review; converged at round 2 per orchestrator judgment), the new Ready-to-Run row in `plans/PLAN_INDEX.md`, and the 2026-04-29 fix-issues sprint record + FINALIZED stamps for both 2026-04-27 and 2026-04-29 sprints in `SPRINT_REPORT.md`. CI initially failed on the midnight ET window from [Issue #132](https://github.com/zeveck/zskills-dev/issues/132) (`Intl.DateTimeFormat('en-US', { hour12: false })` defaults to `hourCycle: 'h24'`, emitting `24:HH ET` instead of `00:HH ET` for the midnight hour); rerun outside the window passed; user merged. **Phase F's ADAPTIVE_CRON_BACKOFF entry is now ready to run.**

- **2026-04-30 (later)** — `ADAPTIVE_CRON_BACKOFF.md` (issue #110) executed via PR-mode chunked `finish auto` on `feat/adaptive-cron-backoff`. **Scope: Mode A only** (defer counter at Step 0 Case 3 — solves clean defer pile-up); **Mode B** (failure-fire pile-up where Step 0 is never reached — different machinery, 3 untested bump-check options) explicitly deferred to follow-up [Issue #134](https://github.com/zeveck/zskills-dev/issues/134) per Phase 1 WI 1.0. [PR #138](https://github.com/zeveck/zskills-dev/pull/138) accumulated 4 phase commits: Phase 1 `685d03c` (counter machinery + Step 0 sentinel-recovery prelude with cadence-sanity check + Case 3 decision rule with 3-attempt CronCreate retry + Case 4 + Case 1 + Phase 5b + `/run-plan stop` cleanup), Phase 2 `6131105` (documentation in `references/finish-mode.md` backoff schedule table + 5 reset triggers + DA4/DA5/A1/N2/N4 prose; new step 5 in `references/failure-protocol.md`), Phase 3 `ff24d74` (`tests/test-runplan-defer-backoff.sh` with 14 functional + 2 anchor cases; pure-bash `defer_backoff_step()` extracted from SKILL.md prose mirroring `tests/test-phase-5b-gate.sh:51-92`), Phase 4 `88f414b` (register new test in `tests/run-all.sh` line 52; extend `tests/test-skill-invariants.sh` with 4 #110 anchors → 36→40 pass). Plan frontmatter `status: complete` (`6cd561e`); issue #110 closed via Phase 5b's `gh issue close` with summary comment + commit hashes. PR #138 awaiting merge as of session end. One self-race observed during Phase 4: recurring `*/1` cron fired while phase work was in progress because the tracker wasn't marked 🟡 In Progress before work began (the new Mode A backoff machinery would have handled this if marked); cron deleted explicitly to stop spurious fires. **Phase F ADAPTIVE_CRON_BACKOFF entry done modulo PR #138 merge.**

- **2026-05-01** — [PR #138](https://github.com/zeveck/zskills-dev/pull/138) (`ADAPTIVE_CRON_BACKOFF.md`, issue #110) merged 2026-04-30T22:06 UTC, merge commit `3a49a36`. Phase F's two ADAPTIVE_CRON_BACKOFF entries flipped `[~]` → `[x]`. Mode A defer-pile-up backoff is now live; Mode B (failure-fire pile-up) follow-up is open as Issue #134 — see Open issues subsection below for routing.

- **2026-04-30 (later)** — `/fix-issues 132 133 auto` sprint (PR mode resolved from `execution.landing: "pr"` config). Both issues clear-and-doable per the Open Issues subsection. 2 parallel agents in worktrees on `fix/issue-NNN`; #132 agent crashed mid-task with the recurring "let me wait for the monitor" hallucination (now 6/7 dispatches across two sessions), but had already completed all the worktree work — orchestrator re-ran tests, sanity-reviewed diff, committed. #133 agent reported back cleanly. Both PRs landed: [#141](https://github.com/zeveck/zskills-dev/pull/141) (issue #132, merge `43a2071`; required a fix-up commit because `hour12: false` + `hourCycle: 'h23'` is non-portable per MDN — older Node/ICU silently ignores hourCycle when hour12 is set; fix-up dropped `hour12: false` and added a `parts.hour === '24'` → `'00'` belt-and-suspenders), [#142](https://github.com/zeveck/zskills-dev/pull/142) (issue #133, merge `b77d589`; CI pass first try; rebased after #141 merge moved main forward). #133 fix declined option 3 (tracking marker + hook block) per issue body's own recommendation in favor of option 1 (past-failure prose preamble) + option 2 (script extraction to `poll-ci.sh`) — declared option 3 "overkill for a polling step" and demonstrated mechanical enforcement via "agent must invoke a named script" without cross-skill hook complexity. Phase F's Open Issues entries for #132 and #133 flipped `[ ]` → `[x]`. **Pre-existing failure** observed on both worktrees and main: `tests/test-update-zskills-migration.sh` case 6c (`detect-language.sh` cohabitation, originated in PR #140 DRAFT_TESTS Phase 6, `522cc9e` — registered in script-ownership but missing from `tier1-shipped-hashes.txt`). Out of scope for this sprint; should be filed as a separate issue or rolled into a follow-up.

- **2026-05-01 (recovery)** — The "pre-existing failure" referenced in the prior drift log entry turned out to be **NOT pre-existing** (orchestrator-discipline failure in the framing). Investigation revealed: `tests/test-update-zskills-migration.sh` case 6c contained a `pass "shallow clone — skipped (warning)"` short-circuit that silently treated the test as PASSING under shallow clones (default `actions/checkout@v4` `fetch-depth: 1`). This made case 6c invisible in CI for ~24h while drift accumulated on `main` across PRs #128, #131, #135-#142. Branch protection only enforces the `test` status check on PR refs (`refs/pull/N/merge`) — not on `main` HEAD after merge — so post-merge red on main was completely unsignaled. Four-phase recovery landed end-to-end: [PR #145](https://github.com/zeveck/zskills-dev/pull/145) (Phase A, `509afae`) restored main green by backfilling 10 drifted Tier-1 blob hashes (apply-preset.sh, briefing.cjs, compute-cron-fire.sh, detect-language.sh, land-phase.sh, plan-drift-correct.sh, post-run-invariants.sh, sanitize-pipeline-id.sh, worktree-add-safe.sh, write-landed.sh). [PR #147](https://github.com/zeveck/zskills-dev/pull/147) (Phase B+E, `deb955f`) replaced case 6c's skip-as-pass with hard `fail` + real `skip` accumulator, set CI `actions/checkout@v4` to `fetch-depth: 0`, AND added a stricter unconditional drift invariant in `tests/test-skill-invariants.sh` (40→41 PASS). [PR #148](https://github.com/zeveck/zskills-dev/pull/148) (Phase C, `2107db3`) added explicit `Bash`-tool-`timeout: 600000` guidance and an anti-pattern callout against `Monitor`/`BashOutput` retry to 4 skills (`run-plan`, `fix-issues`, `verify-changes`, `do`) — root cause of the 6+ subagent crashes was that the test suite (~230s) exceeded the default Bash 120s timeout, agents retried with `Monitor`, and the wake events don't reliably deliver to one-shot subagents. [PR #149](https://github.com/zeveck/zskills-dev/pull/149) (Phase D, `bf6dd32`) added an auto-issue canary: post-merge red Tests on main now files (or comments on) a `main-broken` labeled issue. Total: 4 PRs, 1697→1698 tests, all 4 post-merge CI runs on main green, ~24h-old gap closed. Memory anchor `feedback_pre_existing_paper_over.md` (TBD) recommended to the user.

- **2026-04-30 (issues filed)** — Three follow-up issues filed during this session: [#132](https://github.com/zeveck/zskills-dev/issues/132) (`tests/test-briefing-parity.sh` midnight ET `Intl.DateTimeFormat` h24 quirk in `briefing.cjs` — one-line fix specced via `hourCycle: 'h23'`; regression test plan included; affects ~4% of CI runs landing in 00:xx ET window), [#133](https://github.com/zeveck/zskills-dev/issues/133) (`/commit pr` Step 6 CI poll skipped without enforcement — proposed mechanical fix via tracking marker + hook block; light-touch fixes (past-failure prose, script extraction) deemed insufficient per user feedback during PR #131's ROG-discovered miss), [#134](https://github.com/zeveck/zskills-dev/issues/134) (Mode B failure-fire pile-up backoff, follow-up to #110, filed by Phase 1 WI 1.0 of `ADAPTIVE_CRON_BACKOFF.md`).

- **2026-04-30** — `DRAFT_TESTS_SKILL_PLAN.md` landed end-to-end via PR-mode chunked `finish auto` (6 PRs over a single session). Refine via PR #120 (2026-04-29) absorbed post-2026-04-24 ecosystem changes. Then 6 phase PRs: #124 (Phase 1: skeleton + `parse-plan.sh` parser with fenced-code-block-aware checksum gate + 3-predicate AC-ID classifier + 7 fixtures, +62 tests, `2cf6897`), #135 (Phase 2: `detect-language.sh` + `insert-prerequisites.sh` for no-test-setup `## Prerequisites` insertion + 9 fixtures, +53 tests, `e7b4d66`; absorbed PR #122 SKILL_FILE_DRIFT_FIX mid-run via two trivial conflicts), #136 (Phase 3: `append-tests-section.sh` + `draft-orchestrator.sh` with parsed-state-driven single-source-of-truth delegate/ac-less skip + 4 fixtures, +64 tests, `b1b8906`), #137 (Phase 4: `review-loop.sh` + `coverage-floor-precheck.sh` + `convergence-check.sh` adversarial QE-persona loop with **orchestrator-judgment convergence** — refiner self-call ignored, mechanical 4-condition disposition-table check; merged-candidate coverage-floor pre-check; exit codes 0/2/3/6; +10 fixtures, +79 tests, `c9ebf31`), #139 (Phase 5: `gap-detect.sh` + `append-backfill-phase.sh` + 4 more scripts; broad-form heading rules with fenced-code-block awareness for backfill insertion AND `## Test Spec Revisions` placement; backticked-token-required-for-MISSING regression guard against prose-token false-positive; parsed-state enrollment of backfill phases in coverage floor; frontmatter complete→active flip; +10 fixtures, +103 tests, `56df394`; first push CI failed because `git grep` found the supposedly-absent backticked token in the AC body itself once committed — fix excluded the plan file from the search via `:(exclude)<plan-rel>` pathspec + new `git_isolate_dir` test helper, second push CI green and auto-merged), #140 (Phase 6: 11 conformance checks in `tests/test-skill-conformance.sh` (one per WI 6.3 sub-bullet) covering frontmatter, tracking-marker, NOT-a-finding list, zero-findings-valid, coverage-floor, **orchestrator's judgment** memory anchor, broad-form checksum-boundary, broad-form backfill insertion, broad-form TSR placement, fenced-code-block-aware boundary, hardened jq-absence; worked example under `tests/fixtures/draft-tests/examples/`; mirror via `scripts/mirror-skill.sh draft-tests`; finalize-marker contract documented; +18 tests, `522cc9e`; verifier dispatched inline due to org agent-dispatch usage limit reached partway through, caveat documented in commit message and phase report). Tests 1213→1670 (+457 net new — 379 own across the plan + 78 absorbed from concurrent merges). Plan frontmatter `status: complete; completed: 2026-04-30`. **Phase F's DRAFT_TESTS_SKILL_PLAN entry is done; new `/draft-tests` skill shipped, sister to `/draft-plan`, scoped to test specs.** Two notable mid-run incidents both surfaced + fixed inline (skill-framework-repo discipline): Phase 2 stale Tier-1 hash defect caught by verifier (impl re-edited script after registering hash, never re-recorded), and Phase 5 verifier-found `set -u` no-op-branch bug in `append-backfill-phase.sh` masked by impl test's `2>/dev/null`.

---

## TL;DR — execution checklist

Status legend: `[x]` complete · `[ ]` pending · `[~]` in flight (PR open or plan being drafted)

#### Phase A — pre-flight (fixes the tools the plans use to land)

- [x] `/fix-issues 56` — `/commit` respects `execution.landing` (PR #74, merged 2026-04-27)
- [x] `/quickfix ← QF1` — slug-namespace `/draft-plan` review files (PR #79, merged 2026-04-28)
- [x] `/quickfix ← QF2` — orchestrator-judgment convergence fix (PR #82, merged 2026-04-28)
- [x] `/quickfix ← QF4` — `/refine-plan` positional-tail guidance + spaces-in-paths fix (PR #85, merged 2026-04-28)
- [x] `/run-plan plans/IMPROVE_STALENESS_DETECTION.md` — landed via PRs #90, #91, #92 (chunked finish auto, 2026-04-28)

#### Phase B — foundation

- [x] `/run-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md` — landed via PRs #94 (refine-plan), #95, #96, #97, #98, #99, #100 (chunked finish auto, 2026-04-28)

#### Phase C — DEFAULT_PORT reconciliation (mandatory /refine-plan)

- [x] `/refine-plan plans/DEFAULT_PORT_CONFIG.md` — landed via PR #119 (a7d9656, 2026-04-28; absorbed Phase B inline-landing of WIs 1.1–1.3)
- [x] `/run-plan plans/DEFAULT_PORT_CONFIG.md` — landed via PR #125 (da108b4, 2026-04-29; chunked `finish auto` PR mode; all phases (2 + P1.A + 3 + 4 + 5); tests 1213→1347 (+14 own, +59/121 from concurrent merges); CHANGELOG corrected to track auto-backfill as future work, NOT shipped)

#### Phase D — Tier-2 plans (run sequentially to reduce mirror churn)

- [x] `/refine-plan plans/CONSUMER_STUB_CALLOUTS_PLAN.md` — landed via PR #105 (2026-04-28)
- [x] `/run-plan plans/CONSUMER_STUB_CALLOUTS_PLAN.md` — landed via PR #106 (2026-04-29; parallel session)
- [x] `/refine-plan plans/SKILL_FILE_DRIFT_FIX.md` — landed via PR #121 (2026-04-29; 2 rounds; 35+36 findings; refine-2 reframed away `__SNAKE__`/sed mechanism)
- [x] `/run-plan plans/SKILL_FILE_DRIFT_FIX.md` — landed via PR #122 (2026-04-29; PR-mode chunked finish auto; all 5 phases; tests 1213→1272 (+59); helper script + reference doc + drift-warn hook + deny-list + allowlist convention)

#### Phase E — /update-zskills source discovery (must wait for B+C+D)

- [x] `/quickfix ← QF3` — landed via PR #128 (2026-04-30T04:23 UTC, closes Issue #126: `/update-zskills` source-asset probe extension + stop-and-ask replacing silent auto-clone). QF3 was moved to Issue #126 on 2026-04-29 (per `QUEUED_QUICKFIXES.md:69`); PR #128 closed it via the `/fix-issues 123 126 93 89 110` sprint that also landed PR #127 (issue #123 test-clobber), PR #129 (issue #93 hook bug), PR #130 (issue #89 test gap).

#### Phase F — independent plans (any order, post-Phase B is safest)

For each item: `/refine-plan` first to absorb drift introduced by Phase B / C / D landings since the plan was authored, then `/run-plan`. Skip the refine step only if you've verified the plan has no touchpoints with what's landed since.

- [x] `/refine-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — landed via PR #103 (2026-04-28)
- [x] `/run-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — landed via PR #109 (2026-04-29; closes Issue #65)
- [x] `/refine-plan plans/DRAFT_TESTS_SKILL_PLAN.md` — landed via PR #120 (efd5c28, 2026-04-28; absorbed post-2026-04-24 ecosystem changes)
- [x] `/run-plan plans/DRAFT_TESTS_SKILL_PLAN.md` — landed via PRs #124, #135, #136, #137, #139, #140 (2026-04-29 → 2026-04-30). All 6 phases complete; +457 tests (1213 → 1670). New `/draft-tests` skill (sister of `/draft-plan`, scoped to test specs) with 12 Tier-1 scripts (`parse-plan.sh`, `detect-language.sh`, `insert-prerequisites.sh`, `append-tests-section.sh`, `draft-orchestrator.sh`, `coverage-floor-precheck.sh`, `convergence-check.sh`, `review-loop.sh`, `gap-detect.sh`, `append-backfill-phase.sh`, `insert-test-spec-revisions.sh`, `flip-frontmatter-status.sh`, `re-invocation-detect.sh`, `verify-completed-checksums.sh`), 40 fixtures, 11 conformance checks, worked example under `tests/fixtures/draft-tests/examples/`. Load-bearing invariants: orchestrator-judgment convergence (refiner self-call ignored), broad-form section boundary with fenced-code-block awareness, backticked-token-required-for-MISSING (prose-only ACs never trigger), backfill phases enrolled in coverage-floor pre-check via parsed-state, `## Test Spec Revisions` placed AFTER `## Drift Log` / `## Plan Review` (closes /refine-plan checksum-boundary cross-skill interaction). Phase 5 surfaced + fixed two real bugs (gap-detect's `git grep` finding the AC's own backticked token; `set -u` no-op-branch crash). Phase 6 verifier dispatched inline due to org agent-dispatch usage limit; caveat documented.
- [x] `/refine-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md` — landed via PR #146 (1573479, 2026-05-01). Two stacked refine commits on `feat/quickfix-do-triage`: first commit `52079e7` was a single-agent run after a dispatch architectural mismatch (`/refine-plan` wrapped in `Agent` → subagent had no `Agent` tool → multi-agent loop collapsed; agent honestly disclosed via tool-list inspection). Second commit `ba2120f` re-ran via the `Skill` tool from a top-level session for proper multi-agent. Round 1: 25 substantive findings (13 reviewer + 12 DA in parallel) → 24 fixed + 1 justified-not-fixed. Round 2: 10 unique substantive findings (housekeeping drift from round-1 structural changes) → 10 fixed. Total 35 findings dispositioned, 0 unresolved. Memory anchor `feedback_multi_agent_skills_top_level.md` recorded the gotcha; Issue [#143](https://github.com/zeveck/zskills-dev/issues/143) proposes a preflight Agent-tool-required check on the five multi-agent skills (`refine-plan`, `draft-plan`, `draft-tests`, `research-and-plan`, `research-and-go`) so this fails loud at the next occurrence.
- [ ] `/run-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md` — **next**: 5 phases (1a, 1b, 2a, 2b, 3) all `⬚`. Triage gate + inline plan + fresh-agent review for `/quickfix` and `/do`; tests for both; cross-cutting CLAUDE_TEMPLATE.md + full-suite + follow-up issue.
- [x] `/draft-plan plans/ADAPTIVE_CRON_BACKOFF.md` — landed via PR #131 (2026-04-30; `/draft-plan` 2 rounds adversarial review; Mode A only; Mode B deferred to #134)
- [x] `/run-plan plans/ADAPTIVE_CRON_BACKOFF.md` — landed via PR #138 (2026-04-30T22:06 UTC, merge commit `3a49a36`; 4 phase commits `685d03c`/`6131105`/`ff24d74`/`88f414b`; plan `status: complete` `6cd561e`; Issue #110 closed via Phase 5b)
- [x] `/refine-plan plans/ZSKILLS_MONITOR_PLAN.md` — landed via PR #101 (2026-04-28)
- [x] `/run-plan plans/ZSKILLS_MONITOR_PLAN.md` — landed via PRs #102, #104, #107, #108, #111, #113, #115, #116, #117 + #118 bookkeeping (2026-04-28 → 2026-04-29). All 9 phases complete; +270 tests (943 → 1213). New `/work-on-plans` + `/zskills-dashboard` skills; HTTP server with drag-drop dashboard; `/plans rebuild` migrated to Python aggregator.
- [x] `/draft-plan plans/PR_LANDING_UNIFICATION.md` — extract canonical `gh pr create` + CI poll + fix-cycle + auto-merge pattern into a new `/land-pr` skill consumed by all 5 PR-creating skills. [PR #77](https://github.com/zeveck/zskills-dev/pull/77) merged 2026-04-28; plan now on main.
- [ ] `/refine-plan plans/PR_LANDING_UNIFICATION.md` *(highest drift risk — plan was authored against pre-PR-#75 main; refine to absorb the merged QF/issue fixes)*
- [ ] `/run-plan plans/PR_LANDING_UNIFICATION.md`
- [ ] `/refine-plan plans/SKILL_VERSIONING.md` *(plan landed via PR #144 on 2026-05-01; agent eval flagged a hardcoded "25 core skills" check in Phase 3.2 that fails today since `/draft-tests` is now the 26th — refine MUST update before run; also touches `skills/commit/SKILL.md` Phase 5 which collides with PR_LANDING_UNIFICATION's `/land-pr` extraction, so run AFTER PR_LANDING_UNIFICATION)*
- [ ] `/run-plan plans/SKILL_VERSIONING.md` *(date+hash hybrid versioning system; touches `skills/update-zskills/SKILL.md` Phase 5a/5b heavily — has its own preflight guard 5a.0 that aborts on open `update-zskills` PRs. Run last among Phase F to minimize collisions.)*

#### Phase G — deferred

- `plans/GITLAB_SUPPORT_DRAFT_PLAN_PROMPTS.md` *(reference; not executable yet — Issue #67)*

#### Open issues — disposition

Issues filed but not yet routed to a phase. Default to running clear-and-doable items as a parallel `/fix-issues` batch; route design-class items to `/draft-plan` first.

- [x] **Issue [#132](https://github.com/zeveck/zskills-dev/issues/132)** — closed 2026-04-30T21:07 ET via PR [#141](https://github.com/zeveck/zskills-dev/pull/141), merge commit `43a2071`. Fix landed in two commits: initial `hourCycle: 'h23'` with `hour12: false` retained (failed CI on older Node), then fix-up `22f1b98` dropped `hour12: false` (per MDN: when both are present, hour12 takes precedence and hourCycle is ignored) AND added `parts.hour === '24'` → `'00'` belt-and-suspenders. +5 midnight-ET regression assertions in `tests/test-briefing-parity.sh` Phase 4.
- [x] **Issue [#133](https://github.com/zeveck/zskills-dev/issues/133)** — closed 2026-04-30T21:09 ET via PR [#142](https://github.com/zeveck/zskills-dev/pull/142), merge commit `b77d589`. Implemented **option 1 + option 2** per the issue body's recommendation (option 3 = tracking marker + hook explicitly declined as overkill). New `skills/commit/scripts/poll-ci.sh` (57 lines, executable); `modes/pr.md` Step 6 prose updated with `Past failure (2026-04-30):` blockquote and replaces inline block with `bash poll-ci.sh "$PR_NUMBER"` invocation. +2 conformance assertions in `tests/test-skill-conformance.sh`.
- [ ] **Issue [#134](https://github.com/zeveck/zskills-dev/issues/134)** — Mode B failure-fire pile-up backoff (follow-up to #110). **Route: `/draft-plan` first, then `/run-plan`.** Bump-check has 3 untested architectural options — same shape that got #110 itself deferred from `/fix-issues` to `/draft-plan`. Don't try `/fix-issues` directly; the design surface needs adversarial review.
- [ ] **Issue [#67](https://github.com/zeveck/zskills-dev/issues/67)** — GitLab support. **Route: stays in Phase G.** Hard prerequisites met (SCRIPTS_INTO_SKILLS, SKILL_FILE_DRIFT_FIX, CONSUMER_STUB_CALLOUTS all complete) but still needs a real GitLab project to test against; revisit when that's in hand.

Reasonable parallel batch: **`/fix-issues 132 133`** — different surfaces (`briefing.cjs` vs `skills/commit/` + hooks), no file overlap, both clear-and-doable. PR mode is resolved from `execution.landing: "pr"` in config, so the explicit `pr` token is redundant.

---

## Why this order — the load-bearing constraints

### 1. Pre-flight quickfixes & issues come before every plan

These four items all touch the **tooling that plans use to land**: `/commit`, `/draft-plan`, `/refine-plan`. Landing them first means every subsequent `/run-plan`, `/refine-plan`, or `/quickfix` runs against fixed orchestration code instead of carrying the bugs forward.

| Item | Touches | Why first |
|---|---|---|
| Issue #56 | `skills/commit/SKILL.md` (config-read for `execution.landing`) | `/commit` is invoked at the end of every plan landing; today it ignores the `pr` mode the plans assume. |
| QF1 | `skills/draft-plan/SKILL.md:L126` | Concurrent `/draft-plan` runs collide on `/tmp/draft-plan-review-round-N.md`. |
| QF2 | `skills/draft-plan/SKILL.md` + `skills/refine-plan/SKILL.md` (4 sites total) | Convergence is an orchestrator judgment, not the refiner's self-call; the buggy behavior currently rubber-stamps "CONVERGED" mid-loop. |
| QF4 | `skills/refine-plan/SKILL.md` (Arguments + Phase 2) | Adds positional-tail guidance arg so `/refine-plan plans/X.md anti-deferral focus` works. Useful for the Phase C reconciliation below. |

These are mutually independent — order within Phase A doesn't matter — but **all four must land before Phase B** so the Phase-B/C/D plans don't trip them.

(Issue #58 was originally listed here; closed via PR #73 — see Drift log above.)

### 2. SCRIPTS_INTO_SKILLS_PLAN is the foundation gate

Two plans hard-block on it via in-plan staleness gates:

- `CONSUMER_STUB_CALLOUTS_PLAN.md` — Phase 1 staleness gate halts `/run-plan` if `SCRIPTS_INTO_SKILLS_PLAN` status ≠ `complete`.
- `SKILL_FILE_DRIFT_FIX.md` — Phase 0 has the same gate.

A third plan **overlaps** but doesn't gate:

- `DEFAULT_PORT_CONFIG.md` — duplicates `SCRIPTS_INTO_SKILLS Phase 3a` work items 3a.4c.i/ii/iii (schema field, this-repo config, greenfield template). PLAN_INDEX explicitly says: *"reconcile via /refine-plan after one of the two lands."*

Running `SCRIPTS_INTO_SKILLS_PLAN.md` first is the canonical path because it's the more structural change and the two follow-up plans (CONSUMER_STUB_CALLOUTS, SKILL_FILE_DRIFT_FIX) anchor on its Tier-1 layout.

### 3. DEFAULT_PORT_CONFIG needs `/refine-plan` mid-stream

After Phase B lands, `DEFAULT_PORT_CONFIG.md` Phase 1 work items 1.1–1.3 are already done by `SCRIPTS_INTO_SKILLS_PLAN` Phase 3a. The remaining novel work is **WI 1.4 (backfill logic in `/update-zskills` for existing configs)** plus Phases 2–5.

**Mandatory step**: `/refine-plan plans/DEFAULT_PORT_CONFIG.md` between Phase B and Phase C. The refine pass strips WIs 1.1–1.3 as done-elsewhere and validates the surviving backfill scope. Skipping this means `/run-plan` will spend a phase double-writing the schema field and possibly fail acceptance criteria that test for "field added by this plan."

If you'd rather run `DEFAULT_PORT_CONFIG.md` first, the symmetric reconciliation works (`/refine-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md` after) — but `SCRIPTS_INTO_SKILLS_PLAN` is bigger and more structural, so foundation-first is cleaner.

### 4. CONSUMER_STUB_CALLOUTS and SKILL_FILE_DRIFT_FIX should run sequentially, not in parallel

Both Tier-2 plans add files to `.claude/skills/update-zskills/`:

- `CONSUMER_STUB_CALLOUTS` adds `zskills-stub-lib.sh`.
- `SKILL_FILE_DRIFT_FIX` adds `zskills-resolve-config.sh`.

Both use `rm -rf .claude/skills/update-zskills && cp -a skills/update-zskills/ ...` discipline. Running them in parallel risks the second wiping the first's mirror copy. Sequential execution avoids that with no extra coordination.

There's no hard ordering between the two — pick whichever you'd rather land first. CONSUMER_STUB → DRIFT_FIX is the order matching the Tier-2 priority in PLAN_INDEX.

### 5. QF3 is *deferred by design*

`QUEUED_QUICKFIXES.md` Prompt 3 explicitly states:

> queued instead because (a) low urgency — doesn't break installs, just produces silent re-clone when a non-`/tmp` clone exists; (b) `skills/update-zskills/SKILL.md` is going to churn from active plans (DEFAULT_PORT_CONFIG, SCRIPTS_INTO_SKILLS_PLAN, SKILL_FILE_DRIFT_FIX) — running this now would create a refine-after-rebase loop.

Run QF3 only **after Phases B + C + D-DriftFix** complete. It's anchored on the section name and 4-tier probe rather than line numbers, so it survives the file churn.

### 6. Issue #65 → run the existing plan, not `/fix-issues`

`BLOCK_DIAGRAM_TRACKING_CATCHUP.md` (3 phases, in PR #70) was authored specifically for Issue #65. The plan goes beyond a raw fix and adds:

- Phase 1: core marker migration (19 sites in `add-block` + `add-example`).
- Phase 2: lint guard + 2 new canary test cases.
- Phase 3: framework-coverage CI guard preventing recurrence.

**Use `/run-plan plans/BLOCK_DIAGRAM_TRACKING_CATCHUP.md`** — `/fix-issues 65` would land Phase 1 only and skip the enforcement that prevents the issue from re-emerging on the next batch migration.

The plan is fully independent of the Phase B/C/D chain (block-diagram is its own skill family, no shared files), so it can run any time after Phase A. Doing it after Phase B is mildly safer — `IMPROVE_STALENESS_DETECTION` and the canonical-config helpers will already be in place.

### 7. Independent plans in Phase F

These four plans share no files, no schema fields, and no skill mirrors with each other or with Phase B–E:

- `BLOCK_DIAGRAM_TRACKING_CATCHUP.md` — block-diagram only.
- `DRAFT_TESTS_SKILL_PLAN.md` — new `skills/draft-tests/` skill.
- `QUICKFIX_DO_TRIAGE_PLAN.md` — `skills/quickfix/` + `skills/do/` triage gates.
- `ZSKILLS_MONITOR_PLAN.md` — new `/zskills-dashboard` + `/work-on-plans` skills, adds its own config block.

Run in any order. Two soft considerations:

- **Run after QF2 lands** (which it already has by Phase A). DRAFT_TESTS and QUICKFIX_DO_TRIAGE both reference adversarial-review patterns; if either was authored against the old "refiner self-declares" model, consider an optional `/refine-plan` first. Not strictly required — the convergence behavior change is a mechanical fix that doesn't invalidate plan content.
- **ZSKILLS_MONITOR_PLAN refresh is in PR #70** (`/zskills-monitor` → `/zskills-dashboard`). Run it as-is.

### 8. GITLAB_SUPPORT_DRAFT_PLAN_PROMPTS — defer indefinitely

PLAN_INDEX flags it as `Reference (deferred)`. It's planning prompts for *future* work, not an executable plan. Hard prerequisites: `SCRIPTS_INTO_SKILLS_PLAN`, `SKILL_FILE_DRIFT_FIX`, `CONSUMER_STUB_CALLOUTS_PLAN` all complete + a real GitLab project to test against. Don't `/run-plan` this; revisit when both conditions are met.

---

## Refine-plan checklist

Required:

- [ ] `/refine-plan plans/DEFAULT_PORT_CONFIG.md` — between Phase B and Phase C. Mandatory; the plan duplicates work that Phase B will already have done.

Optional / consider:

- [ ] `/refine-plan plans/DRAFT_TESTS_SKILL_PLAN.md` — only if you suspect the adversarial-review wording in the plan was authored against the pre-QF2 convergence model.
- [ ] `/refine-plan plans/QUICKFIX_DO_TRIAGE_PLAN.md` — same caveat.

Not needed:

- `BLOCK_DIAGRAM_TRACKING_CATCHUP.md`, `ZSKILLS_MONITOR_PLAN.md`, `IMPROVE_STALENESS_DETECTION.md`, `CONSUMER_STUB_CALLOUTS_PLAN.md`, `SKILL_FILE_DRIFT_FIX.md`, `SCRIPTS_INTO_SKILLS_PLAN.md` — all freshly authored or refreshed in PR #70 against current state; no stale assumptions to refine.

---

## Conflict matrix (load-bearing files only)

| File / surface | Touched by |
|---|---|
| `skills/commit/SKILL.md` | Issue #56 |
| `skills/draft-plan/SKILL.md` | QF1, QF2 |
| `skills/refine-plan/SKILL.md` | QF2, QF4 |
| `skills/update-zskills/SKILL.md` | SCRIPTS_INTO_SKILLS_PLAN, SKILL_FILE_DRIFT_FIX, DEFAULT_PORT_CONFIG, CONSUMER_STUB_CALLOUTS_PLAN, QF3 |
| `.claude/skills/update-zskills/` (mirror) | CONSUMER_STUB_CALLOUTS_PLAN, SKILL_FILE_DRIFT_FIX (run sequentially) |
| `.claude/zskills-config.json` schema → `dev_server.default_port` | SCRIPTS_INTO_SKILLS_PLAN Phase 3a, DEFAULT_PORT_CONFIG Phase 1 (overlap → refine) |
| `block-diagram/add-block/SKILL.md` + `add-example/SKILL.md` | BLOCK_DIAGRAM_TRACKING_CATCHUP.md (Issue #65) — isolated |
| `skills/draft-tests/` (shipped 2026-04-30) | DRAFT_TESTS_SKILL_PLAN.md — done |
| `skills/quickfix/` + `skills/do/` | QUICKFIX_DO_TRIAGE_PLAN.md — isolated |
| `/zskills-dashboard` + `/work-on-plans` (new) | ZSKILLS_MONITOR_PLAN.md — isolated |

---

## Source documents

- PR #70: <https://github.com/zeveck/zskills-dev/pull/70>
- Issues: ~~[#56](https://github.com/zeveck/zskills-dev/issues/56)~~ (closed by PR #74) · ~~[#58](https://github.com/zeveck/zskills-dev/issues/58)~~ (closed by PR #73) · [#65](https://github.com/zeveck/zskills-dev/issues/65)
- [PR #75](https://github.com/zeveck/zskills-dev/pull/75) — `/fix-issues` PR-mode gating fix, merged 2026-04-27
- `QUEUED_QUICKFIXES.md` (repo root) — full prompts for QF1–QF4
- `plans/PLAN_INDEX.md` — auto-generated dependency notes
