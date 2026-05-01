# Plan Report — PR Landing Unification

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
