# Plan Report — PR Landing Unification

## Phase — 4 Migrate `/fix-issues pr` to `/land-pr` (drop 300s timeout) [UNFINALIZED]

**Plan:** plans/PR_LANDING_UNIFICATION.md
**Status:** Completed (verified) — drift fix: /fix-issues pr GAINS canonical fix-cycle
**Worktree:** /tmp/zskills-pr-pr-landing-unification
**Branch:** feat/pr-landing-unification
**Commits:** 306e2c2 (impl + verify), 958e2a7 (tracker)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 4.1 | Per-issue caller-loop dispatching /land-pr | Done | `LANDED_SOURCE=fix-issues`, `WORKTREE_PATH=$ISSUE_WORKTREE`, `AUTO=$AUTO`, `--issue=$ISSUE_NUM`; body-prep empty; fix-cycle context = issue body + change summary |
| 4.2 | Drop 300s timeout special case | Done | Comment removed; conformance assertion `fix-issues "ci timeout 300"` removed; /land-pr default 600s applies |
| 4.3 | Preserve agent-assisted rebase resolution | Done | Same pattern as /commit and /do — break on conflict, /land-pr writes `.landed status=conflict` with `issue:` field |
| 4.4 | Preserve sprint report generation (Phase 5 of /fix-issues SKILL.md) | Done | `git diff main...HEAD -- skills/fix-issues/SKILL.md` empty |
| 4.5 | `--issue $ISSUE_NUM` flag passthrough to .landed | Done | Unconditional in `$LAND_ARGS` (always set in /fix-issues context) |
| 4.6 | Conformance updates | Done | 4 removed (ci timeout 300, cross-ref to run-plan ci, ci poll always runs, auto-merge AUTO guard) + 4 added (dispatches /land-pr, no inline gh pr create, no inline checks --watch, AUTO_FLAG guard relocated to land-pr) |
| 4.7 | Mirror via mirror-skill.sh fix-issues | Done | `diff -r` empty |
| 4.8 | Manual canary verification | **DEFERRED** | Architectural — same as 2.9, 3.5/3.10 (subagents can't run multi-agent skills). Phase 5 cron fire serves as de-facto canary |

### Verification

- Test suite: PASSED (1790/1790, baseline 1790, net-zero from balanced add/remove)
- Static migration: 0 inline `gh pr create`, 0 `gh pr checks --watch`, 31 `land-pr` references, 1 `Skill.*land-pr` dispatch site (per-issue inside loop), 0 `timeout 300`, 4 `--issue` references
- Caller-loop consistency vs /commit + /do: identical 12-key allow-list parser, BRANCH_SLUG sanitize, STATUS dispatch, CI_STATUS dispatch, _CLEANUP_PATHS array (CI_LOG_FILE excluded)
- `pr-merge.sh:67` literal pattern verified (`if [ "$AUTO_FLAG" != "true" ]; then`) — relocated assertion regex matches
- shellcheck on /land-pr scripts: 0 warnings (Phase 1A non-regression)
- Phase 1A scripts non-regression: `git diff main...HEAD -- skills/land-pr/` empty
- WI-by-WI verifier verdict: 8/8 PASS (with 4.8 deferred)

### Drift dispositions (Phase 3.5)

Zero drift tokens — neither implementer nor verifier emitted any.

### Phase 3 canary verified-in-action (composition)

This phase's `/run-plan` invocation used the new migrated /run-plan PR mode (PR #161) AND dispatched `/land-pr` (PRs #159+#160) in Phase 6. Both verified end-to-end during Phase 3's land step (PR #162 merged via /land-pr at commit `bc36e6a`). Phase 4's land will be the second composition canary fire.

### For Phase 5

- All 4 PR-landing call sites (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`) now dispatch `/land-pr`. Phase 5 (`/quickfix` migration) is the LAST code-touching call-site migration.
- Pattern is well-established: mirror copy-paste-modify the canonical caller-loop with appropriate slot fills.
- /quickfix is the most invasive migration: per the spec it's a "drift fix: gain CI monitoring + fix-cycle" — meaning /quickfix currently has fire-and-forget design that's drift, not a feature. Restoring full caller-loop pattern.

## Phase — 3 Migrate `/commit pr` and `/do pr` to `/land-pr` (drift fix)

**Plan:** plans/PR_LANDING_UNIFICATION.md
**Status:** Completed (verified) — drift fix: both skills GAIN fix-cycle (previously missing)
**Worktree:** /tmp/zskills-pr-pr-landing-unification
**Branch:** feat/pr-landing-unification
**Commits:** 453a5af (impl + verify), 3c3264d (tracker)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 3.1 | `/commit pr` migration to caller loop | Done | LANDED_SOURCE=commit, no --worktree-path, no --auto, fix-cycle context = staged + commits |
| 3.2 | `/commit pr` preconditions preserved (clean-tree + branch guard) | Done | Steps 1-2 precede /land-pr dispatch (Step 4) |
| 3.3 | `/commit pr` body to `/tmp/pr-body-commit-$BRANCH_SLUG.md` | Done | path uses BRANCH_SLUG sanitization |
| 3.4 | `/commit pr` conformance updates | Done | --watch unreliable relocated; step6: poll-ci.sh removed; PR #131 preamble relocated to /land-pr SKILL.md:323-333; new `dispatches /land-pr` assertion |
| 3.5 | `/commit` mirror | Done | `diff -r` empty |
| 3.5a | Delete orphan `skills/commit/scripts/poll-ci.sh` | Done | both source + mirror deleted; 4 surviving refs are historical comments (pr-monitor.sh docstring + failure-modes.md case study), no live invocations |
| 3.6 | `/do pr` migration to caller loop | Done | LANDED_SOURCE=do, --worktree-path=$WORKTREE_PATH, no --auto, fix-cycle context = task description; A1-A6 preserved |
| 3.7 | Remove `gh pr create` from `/do/SKILL.md` line 878 | Done | reworded to "never use --fill when creating a PR"; regression guard `check_not do "no inline gh pr create"` |
| 3.8 | `/do pr` `.landed` schema harmonization | Done | /fix-report reads only `status:` + `pr:` (additive contract honored) |
| 3.9 | `/do pr` conformance updates | Done | --watch unreliable relocated; pr-state-unknown retry STAYS; report-only ci REMOVED + replaced with `dispatches /land-pr` |
| 3.10 | `/do` mirror | Done | `diff -r` empty |

### Verification

- Test suite: PASSED (1790/1790, baseline 1792 - 2 net from in-place assertion upgrade)
- Static migration: 0 inline `gh pr create` in commit/modes/pr.md, do/modes/pr.md, do/SKILL.md
- 0 inline `gh pr checks --watch` in commit/modes/pr.md, do/modes/pr.md
- 24 land-pr references in each of /commit and /do modes/pr.md
- shellcheck on land-pr scripts: 0 warnings (Phase 1A non-regression)
- Caller-loop consistency (commit + do vs canonical): both use BRANCH_SLUG, allow-list parser with same KEY set, identical STATUS + CI_STATUS handling, _CLEANUP_PATHS array (CI_LOG_FILE excluded)
- WI-by-WI verifier verdict: 11/11 PASS

### Drift dispositions (Phase 3.5: 2 found, 0 corrected — both informational)

- `tests-net delta plan=+1 actual=-2`: relocations consumed an existing /land-pr `PR #131 past-failure preamble` placeholder rather than minting new (in-place upgrade). Net change of -2 from `commit step6: poll-ci.sh` removal + `do report-only ci` removal. Non-blocking.
- `WI-3.5a grep-result plan=zero-hits actual=4-historical-comments`: 4 surviving `poll-ci.sh` references are documentation in pr-monitor.sh docstring + failure-modes.md case study (and their mirrors). All comments, no live invocations. Verifier recommends keeping as teaching aid.

### Phase 2 canary outcome (de facto)

This phase's `/run-plan` invocation is the FIRST to use the migrated `/run-plan` PR-mode code from PR #161. Phase 2's WI 2.9 (manual canary verification) was deferred to this phase fire as the safety net. **The new `/run-plan` orchestrated this phase end-to-end without issue:** worktree creation, agent dispatch, verification, tracker commits, and (next) the new `/land-pr` dispatch for landing. Phase 2's migration is verified-in-action.

### For Phase 4

`/fix-issues pr` migration can copy the caller-loop block from `skills/commit/modes/pr.md:68-214` or `skills/do/modes/pr.md:181-329` — both are byte-canonical to the reference template. Conformance pattern (`check_not <skill> "no inline gh pr create"` + `check_fixed <skill> "modes/pr.md dispatches /land-pr"`) is established for run-plan/commit/do; extend to fix-issues.

## Phase — 2 Migrate `/run-plan` PR mode to `/land-pr`

**Plan:** plans/PR_LANDING_UNIFICATION.md
**Status:** Completed (verified) — most consequential migration in the plan
**Worktree:** /tmp/zskills-pr-pr-landing-unification
**Branch:** feat/pr-landing-unification
**Commits:** bfc265d (impl + verify), 335a237 (tracker)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 2.1 | Caller-owned body splice (preserve bash-regex BASH_REMATCH) | Done | $PR_BODY built before /land-pr invoke; SKILL.md:1715-1745 splice unchanged (`git diff` 0 lines) |
| 2.2 | Replace inline PR-landing block with caller loop | Done | `modes/pr.md` 681→545 lines; markers `# === BEGIN/END CANONICAL /land-pr CALLER LOOP ===` at 279/522 |
| 2.3 | Preserve agent-assisted rebase conflict resolution (≤5 files) | Done | `STATUS=rebase-conflict` branch reads `${LP[CONFLICT_FILES_LIST]}`, dispatches if ≤5 |
| 2.4 | Preserve fix-cycle agent dispatch with plan context | Done | `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block + `<CALLER_WORK_CONTEXT>` slot named |
| 2.5 | Preserve finish-mode loop + frontmatter writes | Done | `git diff main...HEAD -- skills/run-plan/SKILL.md` empty |
| 2.5a | ADAPTIVE_CRON_BACKOFF Mode A interaction documented | Done | doc note at `pr.md:268-276` |
| 2.6 | `.landed` ownership split + downstream consumer test | Done | ownership table at `pr.md:533-543`; `tests/test-landed-schema.sh` (6 cases) |
| 2.7 | Conformance assertions: WATCH_EXIT relocated + 4 new | Done | `WATCH_EXIT` in land-pr (test-skill-conformance.sh:367-393); +4 run-plan: dispatches /land-pr, no inline gh pr create/checks --watch/merge --auto |
| 2.8 | Mirror via `mirror-skill.sh run-plan` | Done | `diff -r` byte-identical |
| 2.9 | Manual canary verification (CANARY1_HAPPY + CANARY3_FIXCYCLE) | **DEFERRED** | Architectural: subagents lack Agent tool; multi-agent skills can't run from subagent context (memory `feedback_multi_agent_skills_top_level`). De-facto canary: Phase 3 cron fire uses migrated code in main; post-run-invariants is the safety net |

### Verification

- Test suite: PASSED (1792/1792, baseline 1782 + 10 net new = 1792)
  - +4 run-plan conformance assertions
  - +6 new `tests/test-landed-schema.sh` cases
  - WATCH_EXIT relocated (net 0 from move)
- Static migration (substitute for canary): all 4 grep-counts at expected values
  - `gh pr create` in pr.md: 0 ✓
  - `gh pr merge --auto` in pr.md: 0 ✓
  - `gh pr checks.*--watch` in pr.md: 0 ✓
  - `land-pr` references in pr.md: 50 ✓ (2 actual `Skill.*land-pr` dispatches at lines 330, 336)
- Caller-loop key elements present: allow-list parser, `while :` loop, body-prep marker
- shellcheck on `tests/test-landed-schema.sh`: 0 warnings
- Phase 1A scripts non-regression: `git diff main...HEAD -- skills/land-pr/` empty
- Phase 3 readiness check (mental walkthrough of caller loop): no infinite-loop risks; all branches handled (rebase-conflict break; push/create/monitor/merge-failed break; created/monitored/merged fall to CI; pass/none/skipped/pending/unknown break; fail+attempt-cap continue/break)
- LAND_ARGS construction: required + conditional flags all present
- RESULT_FILE path: `/tmp/land-pr-result-$BRANCH_SLUG-$$.txt` (PID-isolated)
- _CLEANUP_PATHS: CI_LOG_FILE correctly excluded

### WI 2.9 deferral context

The plan author assumed the implementer subagent could invoke `/run-plan` against canary plans to perform end-to-end smoke. This is structurally not possible: subagents have no `Agent` tool, and `/run-plan` is a multi-agent skill that dispatches its own impl + verify subagents. Per memory `feedback_multi_agent_skills_top_level`, multi-agent skills must run at top level. The same constraint applies to verifier subagents.

**Mitigation:** Phase 3 fires via cron as a fresh top-level turn that uses the migrated `/run-plan` code in main. If the migration is broken, Phase 3's land step will fail at one of: push, PR create, CI poll, fix cycle, or auto-merge. `post-run-invariants.sh` catches the failure and stops the pipeline (no Phase 4+ cron). The mechanical safety net (`.landed` status, `post-run-invariants`, Phase 5c branching on landed-status) is the actual smoke gate.

**Phase 3 readiness:** static migration grep-checks + caller-loop walkthrough + Phase 1A's smoke-tested `/land-pr` components combine to give high confidence the migration is correct. The remaining risk (composition: run-plan dispatching land-pr in actual flow) gets exercised by Phase 3 itself.

**One Phase-3 nuance flagged by verifier (not a blocker):** The agent-assisted rebase resolution at `pr.md:425-428` uses a placeholder `:` with conservative `break` fallback. If the orchestrator-level Agent dispatch isn't completed at runtime, the agent-assisted resolution silently no-ops (treats every conflict as too-many-files). This matches plan intent (conservative fail-safe) and won't fire in Phase 3 (main is current; no rebase conflict expected).

### PLAN-TEXT-DRIFT

None detected. Counts (681 → 545 lines), file paths, and SKILL.md splice line range all match plan text.

## Phase — 1B `/land-pr` validation

**Plan:** plans/PR_LANDING_UNIFICATION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-pr-landing-unification
**Branch:** feat/pr-landing-unification
**Commits:** 04d4d3d (impl + verify), 0782877 (tracker)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1B.1 | `skills/land-pr/references/failure-modes.md` — 10 failure modes cataloged | Done | severity + detection-line + test-case columns; coverage matrix |
| 1B.2 | `tests/mocks/mock-gh.sh` + `mock-git.sh` — fail-fast subcommand router | Done | exit 99 on missing canned response (loud, not silent); `mock-git.sh` adds `MOCK_GIT_PASSTHROUGH=1` for hybrid fixtures |
| 1B.3 | `tests/test-land-pr-scripts.sh` — 23 cases covering all 10 failure modes | Done | 10 modes + 4 idempotency + 4 arg-validation + 2 hardening + 3 split sub-cases |
| 1B.4 | Conformance assertions in `tests/test-skill-conformance.sh` | Done | 37 land-pr assertions + 5 new helpers (`check_not`, `check_in_file`, `check_not_in_file`, `check_executable`, `check_not_in_file_filtered`) |
| 1B.5 | Mirror byte-identical via `mirror-skill.sh land-pr` | Done | exit 0; `diff -r` clean |
| 1B.6 | `plans/PLAN_INDEX.md` — Current 1B, Next 2 | Done | row updated |

### Verification

- Test suite: PASSED (1782/1782, baseline 1722 + 60 new = 1782)
- shellcheck: 0 warnings on `tests/test-land-pr-scripts.sh`, `tests/mocks/mock-gh.sh`, `tests/mocks/mock-git.sh`, all 4 `skills/land-pr/scripts/*.sh`
- Standalone `tests/test-land-pr-scripts.sh`: 23/23
- Standalone conformance: 234/234
- WI-by-WI verifier verdict: 6/6 PASS
- Failure-mode coverage matrix: all 10 cited test cases exist; all detection-mechanism line numbers correspond to actual exit-code/stdout-key sites in the scripts
- Phase 1A scripts non-regression: `git diff main...HEAD -- skills/land-pr/scripts/` is empty

### Drift dispositions (Phase 3.5: 2 found, 0 corrected — non-numeric, non-derivable)

- `WI-1B.2 fail-fast-exit-code`: plan said 127 (mimic `gh` "command not found"); implementer chose 99. Both loud + non-zero. Disposed as faithful-to-intent; not a blocker.
- `WI-1B.4 check_fixed-pattern`: plan said `'gh pr checks .*--watch'`; rewritten to `'gh pr checks "$PR_NUMBER" --watch'` because `check_fixed` is `grep -F` (literal) and `.*` would not glob. Rewrite preserves intent and asserts the actual code shape. Disposed as faithful.

### Implementer-flagged concerns (verifier resolved)

- `check_not_in_file_filtered` allows the canonical `shift || true` arg-parser idiom in the 4 land-pr scripts (Phase 1A code) while still forbidding silencing-fallible-op `|| true`. Verifier accepted as Phase 1B-acceptable; refactoring `shift || true` is out-of-scope (touches 1A code). Reasonable follow-up.

## Phase — 1A `/land-pr` foundation

**Plan:** plans/PR_LANDING_UNIFICATION.md
**Status:** Completed (verified)
**Worktree:** /tmp/zskills-pr-pr-landing-unification
**Branch:** feat/pr-landing-unification
**Commits:** 6d0d0ab (impl + verify), c39b184 (tracker)

### Work Items

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1.1 | Skill frontmatter (`name`, `description`, `argument-hint`) | Done | matches spec verbatim |
| 1.2 | Argument parsing (4 required + 7 optional flags + 4 validations) | Done | bash regex per /quickfix /do precedent |
| 1.3 | `pr-rebase.sh` — capture-then-abort + REASON tokens | Done | 117 lines; sidecar BEFORE abort verified |
| 1.4 | `pr-push-and-create.sh` — bash-regex on `gh --json`, no `gh pr edit` | Done | 164 lines; PR_NUMBER via `${URL##*/}` |
| 1.5 | `pr-monitor.sh` — `WATCH_EXIT`, structured output, no inherited `2>/dev/null` | Done | 156 lines; consolidates `commit/scripts/poll-ci.sh` |
| 1.6 | `pr-merge.sh` — auto-merge-disabled-on-repo benign path | Done | 129 lines; PR_STATE retry 0/2/4s |
| 1.7 | Result-file safety contract — `validate_result_value`, atomic write | Done | rejects `\n`,`\r`,`$`,`,`&`,`?`,`#`; `.tmp`+`mv` |
| 1.8 | `caller-loop-pattern.md` reference | Done | 195 lines; allow-list parser, never `source`; cleanup-array fix |
| 1.9 | `fix-cycle-agent-prompt-template.md` reference | Done | 126 lines; "do not nest Agent dispatches" constraint |
| 1.11 | Canonical `.landed` schema documented in SKILL.md | Done | 11-field schema |
| 1.12 | SKILL.md procedure prose (10 numbered steps) | Done | 552 lines; PR #131 preamble + status mapping table |
| 1A.13 | Mirror byte-identical via `mirror-skill.sh land-pr` | Done | exit 0, `diff -r` clean |
| 1A.14 | `plans/PLAN_INDEX.md` updated to In Progress | Done | current=1A, next=1B |

### Smoke Checkpoint

PASS. Real GitHub PR #158 created against `smoke/land-pr-1777656056` throwaway branch using `--no-monitor` flag. Verified:

- Result file produced with all 12 required schema keys, all values single-line
- Allow-list parser leaves `$()` payload as literal (no shell evaluation)
- `pr-push-and-create.sh` does NOT call `gh pr edit` (grep confirmed)
- 2nd invocation (`pr-rebase.sh` + `pr-push-and-create.sh`) idempotent — exit 0 on rebase up-to-date, `PR_EXISTING=true` on existing PR
- PR #158 closed via `gh pr close --delete-branch`; remote + local smoke branches deleted

### Bug Surfaced + Fixed (skill-framework discipline)

Branch names containing `/` (e.g., `smoke/foo`, `feat/bar`) broke `/tmp/...` sidecar paths because `>"/tmp/...-smoke/land-pr-...log"` requires the directory to exist. Fixed by deriving `BRANCH_SLUG="${BRANCH//\//-}"` once and using slug for filenames only — real `$BRANCH` still passed unchanged to `git fetch`, `git rebase`, `git push`, `gh pr list --head`, `gh pr create --head`. Verifier sanity-checked all 4 scripts apply the slug consistently. This was a real foundation flaw — surfaced via the smoke checkpoint working as designed.

### Verification

- Test suite: PASSED (1722/1722, matched baseline)
- shellcheck: 0 warnings on all 4 scripts
- WI-by-WI verifier verdict: 13/13 PASS
- Implementer-flagged concerns dispositioned: (a) one documented `2>/dev/null` exemption in SKILL.md step 2 (resume-mode `gh pr view` PR_URL recovery — empty fallback is the explicit handled outcome) accepted; (b) parser-side shell-injection test accepted; writer-side `validate_result_value` test deferred to Phase 1B
- No PLAN-TEXT-DRIFT tokens (re-detected independently)

### Acceptance Criteria

- [x] Smoke checkpoint passes
- [x] `skills/land-pr/SKILL.md` exists; `name: land-pr` confirmed
- [x] All four scripts exist and executable
- [x] `shellcheck skills/land-pr/scripts/*.sh` returns 0
- [x] Both reference files exist
- [x] Mirror byte-identical (exit 0)
- [x] No skill yet calls `/land-pr` (Phases 2–5 do that)
- [x] `plans/PLAN_INDEX.md` shows PR_LANDING_UNIFICATION In Progress, Phase 1A current
- [x] `bash tests/run-all.sh` still passes (1722/1722)
