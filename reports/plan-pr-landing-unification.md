# Plan Report — PR Landing Unification

## Phase — 1A `/land-pr` foundation [UNFINALIZED]

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
