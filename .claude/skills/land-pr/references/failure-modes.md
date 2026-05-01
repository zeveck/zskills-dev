# /land-pr failure modes

This document catalogs the 10 failure modes that the four scripts under
`skills/land-pr/scripts/` detect and surface. Each entry names the
failure, its **severity** (block — caller cannot proceed; warn — caller
can settle the PR at a degraded `.landed status`), the **detection
mechanism** in the corresponding script, and the **test case** in
`tests/test-land-pr-scripts.sh` that proves the detection works.

The list is closed: WI 1B.4 conformance assertions and WI 1B.3 tests
are written against this catalog. New failure modes added in Phase 2+
must extend this file AND add a corresponding test.

> **Why this catalog exists.** Phase 1A's research synthesized 5
> callers' divergent CI / merge / push handling into 4 scripts.
> Without an explicit catalog, the "ten ways /land-pr can fail"
> live as scattered comments inside the 4 scripts, and Phase 2–5
> migrations cannot verify they preserved behavior. This file is the
> drift tripwire's spec; `test-skill-conformance.sh` greps for the
> markers, `test-land-pr-scripts.sh` exercises the paths.

## The 10 failure modes

### 1. rebase-conflict — `pr-rebase.sh` exit 10

**Severity:** warn (caller settles `.landed status=conflict`).

**Description:** The feature branch's commits conflict with `origin/$BASE`
during `git rebase`. `git diff --name-only --diff-filter=U` produces a
non-empty list of unmerged files.

**Detection:** `pr-rebase.sh` lines 91–110. CRITICAL: the `U`-state file
list is captured **before** `git rebase --abort`, because post-abort the
working-tree resets and the file list is gone (this fix lives at line
91 — the comment cites `DA2-7 + run-plan/modes/pr.md:30,121` sites
where prior callers got this wrong). The list is written to a sidecar
under `/tmp/land-pr-conflict-files-<slug>-<pid>.txt`; only the path
is emitted on stdout as `CONFLICT_FILES_LIST=…`. Exit code 10
distinguishes conflict from the generic exit 11.

**Test case:** `tests/test-land-pr-scripts.sh` — `rebase-conflict-emits-sidecar`.
Mocks `git rebase` to fail with conflict markers, asserts:
- exit code is 10 (not 11)
- `CONFLICT_FILES_LIST=…` is on stdout
- the sidecar file exists and contains one path per line
- `git rebase --abort` was invoked (counter = 1) AFTER the conflict
  capture, not before

### 2. abort-failed — `pr-rebase.sh` exit 11 / `REASON=abort-failed`

**Severity:** block (working tree is in an intermediate rebase state).

**Description:** After detecting a conflict, the script calls
`git rebase --abort`. If that itself fails, the repo is left in a
partial-rebase state and the caller cannot safely re-invoke /land-pr.

**Detection:** `pr-rebase.sh` lines 102–107. The script emits
`REASON=abort-failed` on stdout and exits 11.

**Test case:** `rebase-abort-failed-surfaces-reason`. Mocks `git
rebase --abort` to return non-zero; asserts exit 11 and stdout
contains `REASON=abort-failed`.

### 3. fetch-network — `pr-rebase.sh` exit 11 / `REASON=network`

**Severity:** warn (transient — caller can retry).

**Description:** `git fetch origin $BASE` failed (no network, auth
denied, ref disappeared from remote).

**Detection:** `pr-rebase.sh` lines 75–80. Stderr is captured to a
sidecar log; only `REASON=network` is on stdout.

**Test case:** `rebase-fetch-network-failure-surfaces-reason`. Mocks
`git fetch` to return non-zero; asserts exit 11 and stdout contains
`REASON=network`.

### 4. push-failed — `pr-push-and-create.sh` exit 12

**Severity:** block (no PR can exist without a pushed branch).

**Description:** `git push` (or `git push -u origin $BRANCH` for the
no-upstream first-time path) failed — auth denial, protected-branch
rule, force-push rejection, etc.

**Detection:** `pr-push-and-create.sh` lines 102–121. Stderr is
captured to `/tmp/land-pr-push-error-<slug>-<pid>.txt`; the script
emits `CALL_ERROR_FILE=<path>` and exits 12. The script has TWO
push paths (with-upstream / without-upstream) — both write the
error sidecar with the same shape.

**Test case:** `push-failed-emits-call-error-sidecar`. Mocks `git push`
to fail; asserts exit 12 and `CALL_ERROR_FILE=` points to a non-empty
file.

### 5. create-failed (network or already-exists race) — `pr-push-and-create.sh` exit 13

**Severity:** block.

**Description:** `gh pr create` failed. Two distinct sub-cases:
- (a) network / auth failure
- (b) **race-bounded create-failed**: a parallel /land-pr just created
  the PR, gh rejects with "already exists" because we read `gh pr list`
  before the parallel create won the race.

**Detection:** `pr-push-and-create.sh` lines 134–141. Stderr captured
to sidecar; `CALL_ERROR_FILE=` and exit 13. Note that `gh pr list`
itself failing is also exit 13 (lines 72–79) — an early-fail variant
of the same severity.

**Test case:** `create-failed-race-bounded`. Mocks `gh pr list` to
return `[]` (no existing PR), then `gh pr create` to fail with
"already exists" stderr. Asserts exit 13, `CALL_ERROR_FILE=` set,
and that `gh pr create` was called exactly once (not retried).

### 6. invalid-pr-number — `pr-push-and-create.sh` exit 14

**Severity:** block.

**Description:** `gh pr create`'s last-line URL ended with a non-digit
suffix (or empty). Triggered by gh-API drift, malformed `--base`, or
gh emitting a non-URL last line. The `${URL##*/}` extraction (per fix
175e4aa) produces a non-numeric value.

**Detection:** `pr-push-and-create.sh` lines 143–158. Validation
regex `^[0-9]+$` against `PR_NUMBER`.

**Test case:** `pr-number-extraction-from-url`. The success path:
mock `gh pr create` returning `https://github.com/o/r/pull/42`,
assert `PR_NUMBER=42` is on stdout, AND assert `gh pr view` was NOT
invoked (counter for `gh pr view` = 0). The failure path:
`pr-number-non-numeric-fails-loud` — mock returns malformed URL,
asserts exit 14.

### 7. pre-flight-failed — `pr-monitor.sh` exit 20

**Severity:** block.

**Description:** Either `--pr` is non-numeric OR `gh auth status`
fails before any polling begins. We surface auth failure loud rather
than silently masking it (past failure: `poll-ci.sh` used
`2>/dev/null` here, hiding gh auth errors).

**Detection:** `pr-monitor.sh` lines 57–73. The check sequence is:
non-numeric `$PR_NUMBER` → exit 20 immediately; then `gh auth status`
→ exit 20 with stderr captured.

**Test case:** `monitor-preflight-non-numeric-pr` and
`monitor-preflight-gh-auth-fails`. Both assert exit 20.

### 8. ci-pending (timeout) — `pr-monitor.sh` `WATCH_EXIT=124`

**Severity:** warn (caller settles `.landed status=pr-ready`; user/cron
can resume with `--pr <num>`).

**Description:** `timeout $TIMEOUT gh pr checks <PR> --watch` returned
124 (timeout(1)'s "still running" signal). We trust 124 explicitly
and ONLY 124 — `--watch`'s own exit codes are unreliable across gh
versions, hence the re-check via plain `gh pr checks` for non-124 cases.

**Detection:** `pr-monitor.sh` lines 102–111. `WATCH_EXIT` (NOT
`WATCH_RC` — see DA2-5; the conformance assertion at
`test-skill-conformance.sh` enforces this name). On 124, emit
`CI_STATUS=pending` and exit 0 cleanly.

**Test case:** `monitor-watch-exit-124-emits-pending`. Mocks the
timeout-wrapped `gh pr checks --watch` to exit 124; asserts
`CI_STATUS=pending` on stdout and exit 0.

### 9. auto-merge-disabled-on-repo (benign) — `pr-merge.sh` exit 0 / `MERGE_REASON=auto-merge-disabled-on-repo`

**Severity:** warn (caller settles `.landed status=pr-ready` —
`MERGE_REQUESTED=false`, but no error).

**Description:** `gh pr merge --auto --squash` failed with stderr
matching the auto-merge-disabled regex (e.g., "auto-merge is not
allowed", "auto merge is disabled", "repo does not allow auto-merge").
This is the expected outcome on repos without auto-merge enabled —
a benign fallback path, not an error.

**Detection:** `pr-merge.sh` lines 94–99. Regex on stderr text:
`auto[-\ ]merge.*not.*allowed|auto[-\ ]merge.*disabled|repo.*does\ not\ allow\ auto[-\ ]merge`.
Returns exit 0 with `MERGE_REQUESTED=false MERGE_REASON=auto-merge-disabled-on-repo`.

**Test case:** `merge-auto-disabled-benign-fallback`. Mocks `gh pr
merge` to return non-zero with stderr matching the regex; asserts
exit 0 (NOT 30), `MERGE_REQUESTED=false`,
`MERGE_REASON=auto-merge-disabled-on-repo`.

### 10. merge-gh-error (non-benign) — `pr-merge.sh` exit 30

**Severity:** block.

**Description:** `gh pr merge --auto --squash` failed with stderr
that does NOT match the auto-merge-disabled regex (e.g., 5xx server
error, branch-protection rule violation, network timeout). We
must NOT silently classify this as benign.

**Detection:** `pr-merge.sh` lines 91–108. Falls through the benign
regex; captures stderr to a sidecar; emits `MERGE_REQUESTED=false
MERGE_REASON=gh-error CALL_ERROR_FILE=<path>` and exits 30.

**Test case:** `merge-gh-error-non-benign-surfaces-call-error`.
Mocks `gh pr merge` to fail with unrecognized stderr (e.g.,
"branch is not protected"); asserts exit 30, `MERGE_REASON=gh-error`,
and `CALL_ERROR_FILE=` points to a non-empty sidecar.

## Coverage matrix

| # | Failure mode                  | Script                  | Exit | Sev   | Test case                                          |
|---|-------------------------------|-------------------------|------|-------|----------------------------------------------------|
| 1 | rebase-conflict               | pr-rebase.sh            | 10   | warn  | rebase-conflict-emits-sidecar                      |
| 2 | abort-failed                  | pr-rebase.sh            | 11   | block | rebase-abort-failed-surfaces-reason                |
| 3 | fetch-network                 | pr-rebase.sh            | 11   | warn  | rebase-fetch-network-failure-surfaces-reason       |
| 4 | push-failed                   | pr-push-and-create.sh   | 12   | block | push-failed-emits-call-error-sidecar               |
| 5 | create-failed (race-bounded)  | pr-push-and-create.sh   | 13   | block | create-failed-race-bounded                         |
| 6 | invalid-pr-number             | pr-push-and-create.sh   | 14   | block | pr-number-extraction-from-url + non-numeric-fails  |
| 7 | pre-flight-failed             | pr-monitor.sh           | 20   | block | monitor-preflight-non-numeric-pr + gh-auth-fails   |
| 8 | ci-pending (WATCH_EXIT=124)   | pr-monitor.sh           | 0    | warn  | monitor-watch-exit-124-emits-pending               |
| 9 | auto-merge-disabled (benign)  | pr-merge.sh             | 0    | warn  | merge-auto-disabled-benign-fallback                |
| 10| merge-gh-error (non-benign)   | pr-merge.sh             | 30   | block | merge-gh-error-non-benign-surfaces-call-error      |

## Idempotency cases (not failure modes, but tested alongside)

These are NOT failures, but the scripts' idempotency contract — re-invoking
the script with no-change state must be a clean no-op. Tests live in
the same file and ride alongside the failure-mode tests so the
idempotency contract is co-tested with the detection contract.

- **rebase-idempotent**: local branch already on top of base; second
  `pr-rebase.sh` call exits 0 with no stdout key emitted.
- **push-create idempotent (existing PR)**: `gh pr list` returns one
  PR; script emits `PR_EXISTING=true` and exits 0 WITHOUT calling
  `gh pr create`. The script does NOT call `gh pr edit --body-file` —
  body update is the caller's responsibility (validated by counter
  for `gh pr edit` = 0).
- **monitor pending → re-poll**: first invocation returns `CI_STATUS=pending`;
  second invocation (after CI completes) returns `CI_STATUS=pass`.
- **merge no-op when --auto-flag=false**: emits `MERGE_REQUESTED=false
  MERGE_REASON=auto-not-requested`, never invokes `gh pr merge`.
