---
title: Concurrency-safe issue claims for /fix-issues dashboard mode
created: 2026-05-21
status: active
---

# Plan: Concurrency-safe issue claims for /fix-issues dashboard mode

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Today, two parallel `/fix-issues 1 dashboard auto` runs both pick `issues.ready[0]` from `.zskills/monitor-state.json` and step on each other — duplicate worktrees on the same issue, two implementers racing, PR-creation collisions. The `execution.max_concurrent_worktrees` cap only counts EXISTING fix worktrees; it does NOT coordinate the *selection* step (Phase 2 dashboard branch, `skills/fix-issues/SKILL.md:1244-1495`) where the issue is chosen before its worktree is materialised.

This plan adds a single-host atomic claim mechanism so:

1. Before `/fix-issues` materialises a per-issue worktree, it acquires an atomic claim on the chosen issue. Acquire-or-fail. Concurrent pipelines whose acquire fails drop that candidate from their dispatch list and try the next one.
2. The `/zskills-dashboard` UI renders a non-interactive "in-flight" chip on the issue's card so the user sees who is working on what at a glance.
3. Claims release on `/land-pr` LAND_OUTCOME=merged, on terminal failures, on Phase 3 partial-dispatch re-saturation, and on Phase 3 1h agent timeout. Claims held across PR-in-flight on LAND_OUTCOME=created are bounded by TTL (default 2h, configurable via `execution.claim_ttl_seconds`). (`monitored` is a STATUS not a LAND_OUTCOME — see D3 / DA3.1.)

## Locked Decisions

These resolve the open design questions surfaced in the `/draft-plan` prompt. The DA pass MUST be free to push back on any of them; refiner must verify before re-locking.

- **D1 — Claim storage: filesystem marker (`.zskills/claims/issue-<N>/`).** `mkdir` is the POSIX atomic acquire primitive (EEXIST = race lost; ENOSPC/EDQUOT/EACCES/EROFS = abort with clear error, NOT race). Inside the subdir, write `claim.json` carrying `schema_version`, `pipeline_id`, `sprint_id`, `issue`, and `started_at` (UTC ISO-8601). Rejected: 1B state-file column (cost: extending strict `ISSUE_COLUMNS` validator at `server.py:475-491` AND adding bash-side `with_monitor_lock` around the currently-lock-free Phase 2 read fence); 1C `/api/claim` HTTP endpoint (cost: fatal-couples cron fires to dashboard liveness). **No `worktree_path` field** — at acquire time the worktree doesn't exist yet, and a post-create-worktree update fence adds complexity for no real benefit (the orchestrator's session already knows which worktree it created; the dashboard chip doesn't need this for in-flight identification — pipeline_short suffices). (DA8.) **No `host_pid` field** — round 2 (DA2.1/DA2.2) revealed that (a) CLAUDE.md does NOT document any `2>/dev/null` exception for `kill -0` (the claim was fabricated), AND (b) the only PID an `acquire` script can self-capture is its own short-lived bash/Python subshell, which exits within ~100ms; the "orchestrator session" is a Claude Code agent, not an addressable PID, so a `kill -0`-based liveness check would lie in both directions (false-stale on the always-dead subshell PID; false-fresh on PID reuse). The PID-liveness fast-path is structurally not addressable under Claude Code's process model, so it is removed entirely. Liveness relies on TTL + the 30s crash-window rule (see D4). (DA2.1/DA2.2.)
- **D2 — Acquire site: post-triage, AFTER partial-dispatch trim, pre-dispatch (2B).** Acquire AFTER Phase 2's un-researched re-filter has replaced `CANDIDATE_ISSUES` (`SKILL.md:1493`), AFTER the orchestrator has selected the picked-list (the model's triage produces this list in prose around `SKILL.md:1523-1533`), AND AFTER the existing partial-dispatch trim at SKILL.md:2002-2057 has reduced `TO_DISPATCH` to the kept prefix. **`TO_DISPATCH` is not currently a fenced bash variable** — it is referenced as if extant at `SKILL.md:2052` but never assigned in a bash fence (the trim at 2052 references-then-reassigns from the orchestrator's prose result). Phase 2 of this plan adds W2.0 (a new fenced `TO_DISPATCH=( <model-built picked numbers> )` materialisation block) immediately AFTER the no-actionable `exit 0` arm (SKILL.md:1923) and IMMEDIATELY BEFORE the partial-dispatch trim's `LIVE_COUNT=` computation (~SKILL.md:2022). The acquire loop (W2.2) is anchored AFTER the partial-dispatch trim completes, so claims are only acquired on the kept prefix — never wasted on the no-actionable exit, never wasted on issues the trim is about to drop. (R1/DA2/R2.1/DA2.5.) No release-on-trimmed-suffix path because we never acquire on the trimmed suffix; no release-on-SLOTS<=0 path because that arm exits before acquire runs.
- **D3 — Release table.** **PR mode** (`skills/fix-issues/modes/pr.md`): canonical release site is the per-issue explicit-finalize block at ~`modes/pr.md:295-298` (alongside the existing `rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$ISSUE_NUM"`), keyed on `$LAND_OUTCOME` (the canonical per-issue outcome set inside the inner `case "$CI_STATUS"` and `case "$STATUS"` arms). **The 10 reachable terminal `LAND_OUTCOME` values** (verified by reading `modes/pr.md` lines 93-273 and grepping `LAND_OUTCOME=` assignments): `merged`, `pr-ready`, `created`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed`. **`monitored` is NOT a reachable `LAND_OUTCOME` value** — it is a STATUS value at line 190 that falls through to the inner `case "$CI_STATUS"` block (lines 193-274), where LAND_OUTCOME is resolved to one of {`merged`, `pr-ready`, `created`, `pr-ci-failing`}. Including `monitored` in the HOLD arm would be dead code. (DA3.1.) Mapping: `merged|pr-ready` → release; `created` → HOLD (PR is in flight per `--no-monitor` arm at modes/pr.md:204-206 — agent created the PR but didn't wait for merge; releasing would let a competing pipeline open a duplicate PR; TTL is the eventual unblock); `pr-ci-failing|rebase-conflict|rebase-failed|push-failed|create-failed|monitor-failed|merge-failed` → release; default/unknown → HOLD (conservative — TTL will sweep). (R2.3, DA3.1.) **Cherry-pick mode** (`skills/fix-issues/modes/cherry-pick.md`): release at the per-worktree terminal `.landed`-write sites — step 5b (`.landed status: full` for successfully-cherry-picked worktrees, ~modes/cherry-pick.md:60-78) and step 5c (`.landed status: partial` for cherry-pick-conflict-skipped worktrees, ~modes/cherry-pick.md:80-92). Note: cherry-pick mode iterates worktrees in PROSE (no fenced `for` loop), so the release call lives inside the per-worktree prose block alongside the `.landed` write — implementers add the `bash $HELPER release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true` line as part of each per-worktree terminal action. (R2.2.) **Direct mode** (`skills/fix-issues/modes/direct.md`): release at four IMPLEMENTED terminal arms — `status: full` (FF-merge success, ~modes/direct.md:131-139), `status: conflict` rebase-conflict (~direct.md:64-72), `status: conflict` FF-refused (~direct.md:92-100), and `status: direct-push-failed` (~direct.md:111-119). The fifth arm `status: direct-verify-failed` is mentioned at modes/direct.md:80 ONLY as a code-comment placeholder (`# after max attempts, write status: direct-verify-failed and continue.`); the actual write-landed-marker dispatch for that terminal is not yet implemented in the codebase. (DA3.3.) Wiring strategy: include the four implemented arms in W2.6c now; document `direct-verify-failed` as an aspirational fifth wiring that activates IF/WHEN the re-verify fix-cycle terminal is implemented as real code (tracked separately — not this plan's scope). (DA2.6 expanded to 5 in round 2 was correct on intent but mis-counted reachable terminals; DA3.3 corrects to 4 implemented + 1 aspirational.) **All modes:** Phase 3 partial-dispatch trim is now BEFORE acquire (D2), so no release-on-trimmed-suffix path is needed. Phase 3 SLOTS<=0 re-saturation `exit 0` runs BEFORE acquire, so no release path needed there either. Phase 3 1h agent timeout → release. **Worktree-add failure** (Phase 3 `create-worktree.sh` non-zero exit): existing behaviour is `exit "$RC"` (sprint-abort), preserved; on the abort path the script MUST release the failed issue's claim AND the suffix of `TO_DISPATCH` not yet dispatched, then exit. (R2.4/R4/DA1.)
- **D4 — TTL default: 7200s (2h)**, configurable via `execution.claim_ttl_seconds`. Covers worst case ~1h agent + ~30min `/land-pr` CI poll + ~30min auto-merge/rebase round, with margin. Uses `started_at` inside `claim.json` (not directory mtime) for sweep age — avoids `atime`/`noatime` mount-option weirdness and `find -mtime` whole-day granularity. **No PID-liveness fast-path** — round 2 (DA2.1/DA2.2) established that (a) CLAUDE.md does NOT document a `kill -0` `2>/dev/null` exception, and (b) the orchestrator session has no stable PID addressable from inside the script's ephemeral subshell. Crash recovery relies entirely on TTL + the 30s crash-window rule below. (DA2.1/DA2.2.) **Crash-window protection:** A metadata-less claim dir older than 30 seconds (dir mtime fallback) is treated as stale by sweep — this catches the mkdir-succeeded-then-writer-crashed-before-claim.json window. The normal mkdir-to-atomic-rename window is sub-second; 30s is conservative. (R7.) **Operational consequence of dropping PID liveness:** on a real orchestrator crash, a fix-issues claim persists for up to 7200s before sweep clears it. Users hitting this in practice can shorten TTL via `execution.claim_ttl_seconds` (min 60s allowed by schema), or manually `rm -rf .zskills/claims/issue-<N>/` (script-internal cleanup is fine; agent-typed inline `rm -r` is hook-blocked, which is correct).
- **D5 — Sweep sites:** (a) Phase 1 preflight, BEFORE the live-worktree defer-all gate (`SKILL.md:874-927`), so a sweep that frees an issue affects the defer decision; AND (b) opportunistic during acquire-after-EEXIST — if `mkdir` fails on an existing claim, parse `started_at`, sweep-and-retry-once if stale.
- **D6 — Dashboard UI: chip on existing card.** Reuses the `skip_reason` chip precedent at `static/app.js:872-884` (PR #449 — renderer-side derivation, no state-schema extension). Chip is non-interactive, lives in a `card-sub` row, tooltip carries the verbatim claim metadata. No `ISSUE_COLUMNS` schema change. Card remains in its current column. **Drag-and-drop is disabled while claimed** — a claimed card represents work another pipeline is acting on; allowing the user to drag-reorder mid-flight invites a "ghost claim" footgun. `buildIssueCard` sets `aria-disabled='true'` and removes `draggable='true'` when `issue.claim` is present. (DA11.)
- **D7 — `monitor-state.json` schema is unchanged.** Claims are not in `monitor-state.json`. Dashboard collector reads `.zskills/claims/` on each snapshot and attaches a `claim` field to each issue dict in the GET response. No `ISSUE_COLUMNS` extension, no validator change, no `_state_lock` interaction.

## What this plan does NOT do

- Cross-host or network-shared claims. Single-host POSIX atomicity is the bound. The devcontainer ext4 is the target. macOS/Docker-Desktop gRPC-FUSE volumes (rare in zskills today) may have mkdir-atomicity weaker than Linux ext4 — if a consumer reports a duplicate-dispatch race despite the mechanism, this is the first place to investigate. (DA12.)
- UI to manually release or steal a claim from the dashboard.
- Auto-merge BLOCKED handling beyond the D3 hold-on-`created`-LAND_OUTCOME rule.
- Refactoring `/fix-issues` dashboard-mode argument parsing or any unrelated cleanup.
- Changes to `ISSUE_COLUMNS` schema. The validator at `server.py:475-491` is untouched.
- Retroactive claim assignment for in-flight worktrees that exist when this PR lands — accept a one-time gap. Existing in-flight work continues as today; the next sprint after merge starts using claims.

## Acceptance Criteria (plan-level)

A1. Two concurrent `/fix-issues 1 dashboard auto` runs from two terminals pick DIFFERENT issues. **Verification:** scripted concurrency test in Phase 4 (`tests/test-fix-issues-claim-race-e2e.sh`, per W4.1) backgrounds two shell acquires for the same issue number; exactly one succeeds, the loser observes EEXIST and exits non-zero. Filename pinned to match W4.1 / W4.4 (F2 fix — earlier draft had inconsistent `test-fix-issues-claim-race.sh` here vs. `-race-e2e.sh` in W4.1).

A2. Dashboard renders an in-progress chip on claimed issues; chip disappears within one snapshot poll after release. **Verification:** Phase 3 unit test on `collect.py` asserts `claim` field populated when `.zskills/claims/issue-<N>/claim.json` exists; Phase 3 unit test on `app.js renderIssues` asserts chip DOM is generated when `claim` field present.

A3. Stale claim (forced `started_at` to NOW - 3h) is swept on the next `/fix-issues dashboard` fire. **Verification:** Phase 4 test creates a claim with forced-old `started_at`, runs the Phase 1 sweep script, asserts the claim directory is gone.

A4. Each enumerated release path actually releases. **Verification:** Phase 2 + Phase 4 tests cover (a) the 10 reachable `LAND_OUTCOME` values in PR mode (`merged`, `created`, `pr-ready`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed` — `monitored` is a STATUS, not LAND_OUTCOME, per DA3.1), (b) the cherry-pick step-5b/5c release sites, (c) the 4 IMPLEMENTED direct-mode terminal arms (FF-merge success, rebase-conflict, FF-refused, direct-push-failed; `direct-verify-failed` is currently a code-comment placeholder per DA3.3 — see W2.6c), and (d) the worktree-add-failure sprint-abort release. One parameterised test per mode in `tests/test-fix-issues-claim-release-{pr,cherry-pick,direct}.sh`.

A5. `bash tests/run-all.sh` green including new claim tests; mirror `diff -rq skills/<name>/ .claude/skills/<name>/` empty for both `fix-issues` and `zskills-dashboard`; no new `2>/dev/null` on fallible ops in changed files.

A6. Conformance test confirms `.zskills/claims/` operations pass BOTH `hooks/block-unsafe-generic.sh` AND `hooks/block-unsafe-project.sh.template`. The SKILL.md / mode-file fences MUST NOT contain any inline `rm -r` / `rm -rf` against `.zskills/claims/` — they always invoke `claim-issue.sh release` (script-internal `rm -rf` is fine because the hook only sees the agent's typed Bash tool command, not the script body). (R2/R5/DA3.) The conformance test grep-asserts: zero hits for `\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)[[:space:]]+\.zskills/claims` in `skills/fix-issues/SKILL.md`, `skills/fix-issues/modes/*.md`, and any test file outside `claim-issue.sh` itself.

A7. Single-pipeline `dashboard` mode behaviour is byte-for-byte identical to today when only one `/fix-issues` is running. **Verification (two-layer per DA3.4):** (a) MECHANISM LAYER — Phase 4 `tests/test-fix-issues-claim-regression-single.sh` sources `claim-fence-helpers.sh` and drives `acquire_for_dispatch_list` on a single-pipeline call; asserts the resulting survivor `TO_DISPATCH` is byte-identical to the input (no perturbation absent contention). (b) INTEGRATION LAYER — PR-time manual repro: run `/fix-issues 3 dashboard auto` once against a stub fixture; record the selection order; attach to PR body as evidence selection matches the pre-claim baseline. Earlier draft attempted a golden-file automated regression but `/fix-issues` is not bash-test-invocable.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Claim primitive script + fence-helpers library + config + unit tests | ⬚ | | |
| 2 — fix-issues acquire + per-mode release wiring (PR + cherry-pick + direct) | ⬚ | | |
| 3 — Dashboard collector + renderer chip (drag-disabled) + fingerprint fix | ⬚ | | |
| 4 — E2E concurrency test + baseline race test + /cleanup-merged sweep + conformance | ⬚ | | |

---

## Phase 1 — Claim primitive script + config + unit tests

### Goal

Create a single shared helper script `claim-issue.sh` exposing all claim operations as subcommands. Add the `execution.claim_ttl_seconds` config field. Add unit tests for the primitive in isolation, including the EEXIST-vs-ENOSPC distinction.

### Work Items

- [ ] **W1.1** — Create `skills/fix-issues/scripts/claim-issue.sh`. Subcommands:
  - `acquire <N> --pipeline-id <id> --sprint-id <id>` — `mkdir .zskills/claims/issue-<N>` and on success write `claim.json` ATOMICALLY: write to `.zskills/claims/issue-<N>/claim.json.tmp` then `os.replace` (Python) to `claim.json`. The `claim.json` body: `{schema_version, pipeline_id, sprint_id, issue, started_at}` — NO `worktree_path` (DA8), NO `host_pid` (DA2.1/DA2.2 — the script's self-captured PID is meaningless under Claude Code's process model; see D1/D4). If the atomic-write step fails after mkdir succeeded, the script `rmdir`s the claim dir before returning non-zero (no stub leak). Exit codes: 0 = acquired, 10 = EEXIST race lost (claim already held), 11 = other mkdir failure (EACCES/ENOSPC/EDQUOT/EROFS — abort with stderr diagnostic). Exit 10 vs 11 distinguished by inspecting `mkdir` stderr — DO NOT swallow with `2>/dev/null`. Map `File exists` → 10; everything else → 11. **Inside `claim.json` write/parse use Python `json` stdlib (no jq, per CLAUDE.md).**
  - `release <N> [--require-pipeline <id>]` — refuse if claim's `pipeline_id` doesn't match (prevents accidental cross-pipeline release). On match, **per-file removal: `rm -f ".zskills/claims/issue-${N}/claim.json"` then `rmdir ".zskills/claims/issue-${N}"`**. Per-file form is mandatory (not a fallback): `block-unsafe-project.sh.template:488` blocks all `rm -r ... .zskills/...` typed inline by an agent; only `rm -rf "$dir"` INSIDE this script body is hook-invisible (the hook sees the agent's Bash tool command, not the script body) — but the per-file shape is simpler, safer, and equally atomic in practice (claim.json removal then empty-rmdir). (R2/DA3.) Exit 0 on release, 0 on already-absent (idempotent), 12 on pipeline-mismatch.
  - `is-stale <N>` — read `claim.json`, parse `started_at`, compare to `NOW - TTL`. **Crash-window:** if the dir exists but `claim.json` is missing AND dir mtime is older than 30 seconds, treat as stale (catches mkdir-succeeded-then-writer-crashed). (R7.) Exit 0 = stale, 1 = fresh, 2 = no claim. TTL resolved from `execution.claim_ttl_seconds` (default 7200). Use Python for ISO-8601 parse (no `date -d` portability surprises). **No `kill -0` liveness check** — see D4 / DA2.1 / DA2.2.
  - `sweep` — iterate `.zskills/claims/issue-*`, call `is-stale` on each, release stale ones (using the script's own internal release path; do NOT shell out per-iteration). Prints one stderr line per swept claim (`fix-issues claims: swept stale claim issue-<N> pipeline=<id> age=<seconds>s reason=<ttl|metadata>`). Idempotent.
  - `release-suffix <N1> <N2> ... --require-pipeline <id>` — bulk-release helper used by Phase 2's sprint-abort path (R2.4). Calls `release` per N; collects exit codes; emits a single stderr summary line. Useful so the SKILL.md fence on the `create-worktree.sh` abort path can loop the suffix without exposing the for-loop in skill prose.
  - `list` — pure read; emit one TSV line per live claim: `<N>\t<pipeline_id>\t<age_seconds>`. (No worktree column — see D1 / DA8.) Used by dashboard collector and human debugging.
- [ ] **W1.2** — Mirror the script under `.claude/skills/fix-issues/scripts/claim-issue.sh` via `bash scripts/mirror-skill.sh fix-issues`.
- [ ] **W1.2.5** — Create `skills/fix-issues/scripts/claim-fence-helpers.sh` — a small sourceable shell function library defining two functions: `sweep_stale_claims()` (calls `claim-issue.sh sweep`, idempotent) and `acquire_for_dispatch_list()` (iterates `TO_DISPATCH`, calls `claim-issue.sh acquire` for each, rebuilds the array from survivors). The Phase 2 SKILL.md fences source this library and call the functions; Phase 4 tests source the same library and test the functions directly. Eliminates inline-vs-extracted fence drift between test and runtime. (DA15.) Mirror to `.claude/skills/fix-issues/scripts/`.
- [ ] **W1.3** — Add `execution.claim_ttl_seconds` to `config/zskills-config.schema.json` (number, default 7200, min 60). Extend `update-zskills` Step 3.6 backfill if that is the convention for new fields (verify by reading update-zskills SKILL.md — do not assume).
- [ ] **W1.4** — Extend `.claude/skills/update-zskills/scripts/zskills-resolve-config.sh` to export `ZSKILLS_CLAIM_TTL_SECONDS` resolved from the new config field. **Prefer the Python one-liner shape** (CLAUDE.md endorses Python json for non-trivial parses; the `max_concurrent_worktrees` BASH_REMATCH clone fails on pretty-printed nested objects because `[^}]*` excludes `}` characters): `_ZSK_TTL=$("$_ZSK_PYTHON" -c "import json,sys; d=json.load(open('$_ZSK_CFG')).get('execution',{}); print(d.get('claim_ttl_seconds',7200))" 2>/dev/null || echo 7200)`, then `[ "$_ZSK_TTL" -ge 60 ] && ZSKILLS_CLAIM_TTL_SECONDS="$_ZSK_TTL"`, then `unset _ZSK_TTL` at end-of-script alongside the existing `unset _ZSK_*` cleanup. **Interpreter resolution uses `_ZSK_`-prefixed internal** to honour the script's existing env-cleanliness contract (`zskills-resolve-config.sh` line 22: "Unsets `_ZSK_`-prefixed internals at end so caller env stays clean"). At the top of the script, add: `_ZSK_PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"` (uses the public-facing `ZSKILLS_PYTHON` override per CLAUDE.md's documented precedence, with the resolved binary parked in a `_ZSK_`-prefixed internal). Add `_ZSK_PYTHON` to the end-of-script `unset` list. **Do NOT use a bare `PYTHON` variable** — it would pollute the caller's env. (R6/R2.5.)
- [ ] **W1.5** — Write tests under `tests/test-fix-issues-claim-script.sh`:
  - Acquire on fresh slot succeeds, exit 0.
  - Second acquire on same slot exits 10 (EEXIST), preserves first claim's `claim.json` byte-for-byte.
  - Release on matching pipeline_id exits 0; release on mismatched pipeline_id exits 12 and leaves claim intact.
  - Release on absent claim exits 0 (idempotent).
  - `is-stale` returns 0 when `started_at = NOW - 3h` with TTL=7200; returns 1 when `started_at = NOW - 1h`; returns 2 when claim absent.
  - `is-stale` returns 0 when claim dir exists but `claim.json` is missing AND dir mtime > 30s ago; returns 1 when `claim.json` is missing AND dir mtime < 5s ago (in-flight write window). (R7.)
  - `sweep` removes stale claims, leaves fresh ones; emits stderr line per swept claim including `reason=ttl|metadata` (no `pid` reason — DA2.1/DA2.2 dropped the PID-liveness path).
  - `release-suffix 1 2 3 --require-pipeline P` releases all three claims when held by `P`; emits one stderr summary line; refuses cleanly per-issue if any was held by another pipeline (exit non-zero, surviving claims untouched).
  - `list` output is parseable: tab-separated, one line per claim, fields in documented order (NO worktree column per DA8).
  - **Concurrency test (two-backgrounded-bash, lifted from `tests/e2e-parallel-pipelines.sh` shape):** two parallel acquires for the same `N`; assert exactly one exits 0, the other exits 10; assert the winning pipeline's metadata persists in `claim.json`.
  - **Non-EEXIST → exit 11 distinction (EACCES):** force `mkdir` failure via `chmod 0500` on parent (cannot create children) and assert exit 11, NOT 10. **Note**: this tests EACCES specifically; the script lumps EACCES/ENOSPC/EDQUOT/EROFS into one "not-EEXIST" class — the test name reflects "non-EEXIST", not "ENOSPC". Actually exhausting filesystem space for an ENOSPC test (tmpfs of 1MB + fill it) is heavy for a unit test; the script doesn't differentiate within the not-EEXIST class so EACCES is a faithful stand-in. (DA10.)
  - **Atomic-write crash window:** simulate mkdir-success-then-write-failure by `chmod 0500` on the issue subdir after mkdir; assert acquire returns non-zero AND the claim dir is `rmdir`'d (no stub leak). (R7.)

### Design & Constraints

- **`claim.json` schema (locked):**
  ```json
  {
    "schema_version": 1,
    "pipeline_id": "fix-issues.sprint-20260521-010731-foo",
    "sprint_id": "sprint-20260521-010731-foo",
    "issue": 123,
    "started_at": "2026-05-21T01:23:45+00:00"
  }
  ```
  No `worktree_path` (DA8) — the field would be write-once-never-updated; the orchestrator's session owns worktree identity, and the chip doesn't need it for in-flight signalling. No `host_pid` (DA2.1/DA2.2) — the script's self-captured PID is meaningless under Claude Code's process model and the previously-claimed CLAUDE.md `kill -0` `2>/dev/null` exception does not exist (grep -in "kill -0\|exception\|2>/dev/null" CLAUDE.md returns only the prohibition itself). Future fields added with `.get()` defaults in readers. `schema_version` bumps if a breaking change is needed (none anticipated).
- **Atomicity primitive:** `mkdir` (NOT `O_EXCL` open of a regular file) — directory-creation as POSIX atomic is universal across ext4/overlayfs/tmpfs. Reading the prompt's filesystem-marker option, `mkdir` is the simpler primitive than a custom O_EXCL helper.
- **EEXIST vs ENOSPC distinction:** `mkdir` returns non-zero for both, but `errno` differs. From bash, parse `mkdir 2>&1` stderr text. Map `File exists` → exit 10; everything else → exit 11. **Do not use `2>/dev/null`** — the stderr text is load-bearing for the distinction.
- **`release` pipeline-id check (W1.1):** prevents a pipeline from accidentally releasing another pipeline's claim. The implementer of Phase 2/3 release wiring will always pass `--require-pipeline "$PIPELINE_ID"`; the script enforces it.
- **No `2>/dev/null` on fallible ops** (CLAUDE.md). The rule is categorical — CLAUDE.md lines 53-61 list no exceptions. Round 1's claim that `kill -0` was a documented exception was fabricated (verified via `grep -in "kill -0\|exception" CLAUDE.md .claude/rules/zskills/managed.md` → zero hits other than the prohibition itself); DA2.1/DA2.2 surfaced this in round 2 and the PID-liveness mechanism was removed entirely. All `mkdir`/`rmdir`/`rm -f`/Python `json.load` calls in this script propagate stderr to the caller.
- **No jq.** Python stdlib `json` for both write (`json.dumps(..., sort_keys=True)`) and read (`json.load(f)` with `.get()` defaults). Source `zskills-resolve-config.sh` at the top of any fence that references `$ZSKILLS_CLAIM_TTL_SECONDS`.
- **Per-file removal is mandatory** for `.zskills/claims/issue-<N>/` cleanup: `rm -f ".zskills/claims/issue-${N}/claim.json"` then `rmdir ".zskills/claims/issue-${N}"`. Validate `$N` is a positive integer at function entry — reject `0`, empty, non-numeric. (R2.)
- **Hook interaction (verified, not defensive):**
  - `block-unsafe-generic.sh:507-528` (`is_safe_destruct`) requires a literal `/tmp/...` path AND rejects any command containing `$`. So an agent-typed `rm -rf .zskills/claims/issue-${N}` would be blocked twice (no /tmp/, has $). Confirmed by reading the hook source.
  - `block-unsafe-project.sh.template:488` blocks ANY `rm -r|-rf|--recursive ... .zskills` typed inline by the agent — no carve-out for `claims/` or any subtree.
  - **Script-internal `rm -rf` is hook-invisible** (the hook sees the agent's Bash tool command, not the script body). So an internal `rm -rf "$claim_dir"` in `claim-issue.sh` would be permitted. The plan still mandates per-file form: simpler, safer, and equally atomic for our two-file structure (claim.json + dir). (R2/R5/DA3.)
  - **All callers (SKILL.md, modes/*.md, tests) MUST invoke `claim-issue.sh release` — never inline `rm` against `.zskills/claims/`.** Conformance test W4.2 grep-asserts zero inline-`rm` hits outside the helper script itself. (R5.)

### Tests

- Inline at `tests/test-fix-issues-claim-script.sh` per W1.5.
- Conformance: no new entries on `tests/fixtures/forbidden-literals.txt` are needed (the script lives outside `skills/**/*.md`, so the deny-list does not apply). Verify by running `bash tests/test-skill-conformance.sh` after Phase 1.

### Acceptance Criteria

- [ ] `bash tests/test-fix-issues-claim-script.sh` green; covers all W1.5 cases.
- [ ] `bash claim-issue.sh acquire 999 --pipeline-id A --sprint-id S` from one shell succeeds; immediate second invocation from another shell exits 10. (No `--worktree` flag — DA8/DA2.7.)
- [ ] `bash claim-issue.sh release 999 --require-pipeline B` exits 12, leaves claim intact; release with `--require-pipeline A` exits 0, removes claim.
- [ ] `bash claim-issue.sh sweep` with TTL=7200 and `started_at = NOW - 3h` removes the claim and emits the documented stderr line.
- [ ] `bash tests/test-skill-conformance.sh` green (no regression).
- [ ] `bash scripts/mirror-skill.sh fix-issues && diff -rq skills/fix-issues .claude/skills/fix-issues` empty.

### Dependencies

None — this phase establishes the primitive.

---

## Phase 2 — fix-issues acquire + release wiring

### Goal

Wire `claim-issue.sh acquire` into `skills/fix-issues/SKILL.md` Phase 2 (post-triage), the Phase 1 preflight sweep, and ALL release sites enumerated in D3.

### Work Items

- [ ] **W2.0** — **Materialise `TO_DISPATCH` as an explicit bash array** (R1/DA2/R2.1/DA2.4). `TO_DISPATCH` is referenced at `SKILL.md:886, 1992, 2009, 2036, 2051, 2052, 2060-2062` but never `=()`-assigned in any fence — the array is implicitly produced by the orchestrator's prose triage at SKILL.md:1523-1533 ("KEEPS the first N that route to in-batch fix-agent or /do pr"). **Re-anchor (round 2):** insert the materialisation fence AFTER the no-actionable `exit 0` arm at SKILL.md:1923 (so the no-actionable branch never executes the fence) AND immediately BEFORE Phase 3's partial-dispatch trim `LIVE_COUNT=` computation at ~SKILL.md:2022. Concretely, the fence lives between the Phase 3 header at SKILL.md:1947 and the trim block at SKILL.md:2002-2057. Verification: `awk 'NR==1923 || NR==1947 || NR==2002 {print NR": "$0}' skills/fix-issues/SKILL.md` confirms ordering. (R2.1.) The fence body:
  ```bash
  # Materialise the orchestrator's triage pick decision as an explicit bash
  # array so downstream fences (partial-dispatch trim, claim acquire, dispatch
  # loop) have a concrete target. Pre-W2.0, the array existed only as
  # orchestrator-narrative; subsequent fences (line 2036+) referenced it as if
  # extant. The orchestrator MUST substitute the actual picked issue numbers
  # below before executing this fence (driven by the prose at ~SKILL.md:1523-1533).
  TO_DISPATCH=( <picked issue numbers, space-separated> )
  ```
  **Picked-numbers sourcing (DA2.4).** The orchestrator-prose triage at SKILL.md:1523-1533 produces the picked list in markdown narrative ("KEEPS the first N..."). The implementer of this plan MUST ALSO add a small structured-output instruction to the triage prose: "After listing your final picks, emit a single line of the form `PICKS: <num> <num> <num>` (space-separated) as the LAST line of the triage response." Then the W2.0 fence's placeholder `<picked issue numbers, space-separated>` is filled directly from that line at fence-execute time. If no candidates pass triage, the orchestrator emits `PICKS:` (empty list) and W2.0 becomes `TO_DISPATCH=( )` — downstream fences then route through the existing no-actionable arm before reaching the trim, so the empty case is safe. Document this contract in the prose above the W2.0 fence: "The orchestrator MUST emit `PICKS: <numbers>` as the final line of the triage response; the W2.0 fence below reads from that line. Empty picks → `TO_DISPATCH=( )` → no work this fire." This is the only place in the plan where the orchestrator inserts a model-built value into a bash fence; the rest of the new fences are static.
- [ ] **W2.1** — Phase 1 preflight sweep. **Insert ABOVE the live-worktree defer-all gate** (`skills/fix-issues/SKILL.md` line ~874, immediately after Sprint identity construction at line ~872). New fenced bash block:
  ```bash
  # Sweep stale claims so a sweep that frees an issue can affect the
  # defer-all gate decision below. claim-issue.sh sweep is idempotent.
  # `|| true` is permitted here because sweep is best-effort hygiene and
  # does not gate sprint correctness — a failed sweep means stale claims
  # persist until next fire, never duplicate dispatch.
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  . "$CLAUDE_PROJECT_DIR/.claude/skills/fix-issues/scripts/claim-fence-helpers.sh"
  sweep_stale_claims || true
  ```
- [ ] **W2.2** — Phase 2 acquire loop. **Insert AFTER the closing `fi` of the if/elif/fi block at SKILL.md:2053 (NOT after the trim line at 2052 which sits INSIDE the elif body) and BEFORE the dispatch loop that follows it** (round 3 fix per DA3.2). Re-anchoring to the post-`fi` position is load-bearing: the SLOTS<=0 arm `exit 0`s at line 2044 before acquire can run (preserved D3 invariant); the elif branch at lines 2045-2053 truncates `TO_DISPATCH`; the implicit else (SLOTS >= N_REQUESTED, line 2054 comment "Otherwise SLOTS >= N_REQUESTED — proceed") leaves `TO_DISPATCH` untouched. Acquire must fire on BOTH the all-fits-in-slots common case AND the partial-trim case. Anchoring inside the elif body (at line 2052) would silently skip acquire on the common case, leaving the bug in place. **Verification:** `awk 'NR==2045,NR==2057 {print NR": "$0}' skills/fix-issues/SKILL.md` confirms `fi` at line 2053 and the post-`fi` insertion target. (Round 2 reorder per R2.1/DA2.5 — acquire-after-trim eliminates the chip-flicker race and saves 2N mkdir+rmdir round-trips on saturated fires; the trim is claim-independent so it can run first.) The acquire loop operates on the already-trimmed kept-prefix only. New fenced bash block sources `claim-fence-helpers.sh` and calls `acquire_for_dispatch_list "$PIPELINE_ID" "$SPRINT_ID"`. The function:
  - For each `N` in (the trimmed) `TO_DISPATCH`, call `claim-issue.sh acquire $N --pipeline-id "$PIPELINE_ID" --sprint-id "$SPRINT_ID"` (no `--worktree` arg — DA8 removed the field).
  - If acquire returns 0, keep `N` in the dispatch list.
  - If acquire returns 10 (race lost), drop `N` from dispatch and emit `fix-issues: claim race lost for issue $N (concurrent pipeline holds it); skipping.` on stderr.
  - If acquire returns 11 (abort), exit the sprint immediately with stderr diagnostic (filesystem error is not a recoverable race). On abort, release any claims acquired earlier in the SAME loop iteration (the prefix of survivors built up to this point) — wrap the acquire loop with a `trap` that releases the in-flight survivor prefix on non-zero exit.
  - After the loop, rebuild `TO_DISPATCH` from the survivors. If empty, route through a SECOND "no actionable" exit path: emit stderr `fix-issues: all candidates already claimed by concurrent pipelines — nothing to dispatch this fire.`, then `ship_sync_only_or_cleanup` (the existing dashboard-mode helper at SKILL.md:1257-1338) and exit 0.
- [ ] **W2.5** — Release on Phase 3 1h agent timeout. Find the existing "Timed out = failed, period" path at ~SKILL.md:2072-2077. Where the orchestrator declares an agent failed and records "Timed out" in SPRINT_REPORT.md, also call `claim-issue.sh release $N --require-pipeline $PIPELINE_ID`.
- [ ] **W2.5.5** — Release on per-issue worktree-add failure (R4/R2.4). Phase 3 currently does `exit "$RC"` on `create-worktree.sh` failure at SKILL.md:2176-2179 (sprint-abort behaviour, preserved per R2.4 to avoid a cross-cutting behaviour shift). On the abort path: BEFORE `exit "$RC"`, release the failed issue's claim AND bulk-release the suffix of `TO_DISPATCH` not yet dispatched. Implementation: wrap the per-issue `create-worktree.sh` invocation at SKILL.md:2170-2179 with a bash guard that, on non-zero RC, (a) calls `claim-issue.sh release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true` for the failing issue, (b) calls `claim-issue.sh release-suffix "${TO_DISPATCH[@]:$((LOOP_IDX+1))}" --require-pipeline "$PIPELINE_ID" || true` for the not-yet-dispatched suffix, (c) emits stderr diagnostic naming the failing issue, (d) executes the existing `exit "$RC"`. Preserves current sprint-abort semantics; no behaviour change for non-claim users beyond the cleanup of held claims on exit. Document this explicitly in Design & Constraints below.
- [ ] **W2.6a** — Release on PR-mode `/land-pr` outcome (per-issue). **File: `skills/fix-issues/modes/pr.md`**. **Round 2 re-anchor (R2.3):** the canonical release site is the per-issue explicit-finalize block at ~`modes/pr.md:295-298`, immediately alongside the existing `rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$ISSUE_NUM"` and the existing `case "$LAND_OUTCOME"` for sprint outcome. The inner `case "$STATUS"` block at `modes/pr.md:175-191` is NOT the correct site — `created|monitored|merged` fall through to the CI_STATUS case where `LAND_OUTCOME` is actually set, so attaching release logic to STATUS would double-fire on the fall-through path. Keying on `$LAND_OUTCOME` after the inner loop completes is correct because it represents the canonical post-loop outcome, set exactly once per issue. Concretely, modify the existing finalize block:
  ```bash
  # Per-issue explicit-finalize (Plan LAND_PR_BYPASS_HARDENING Phase 2).
  # Remove the per-issue requires.land-pr.<ISSUE_NUM> marker regardless
  # of LAND_OUTCOME. Update sprint-level $SPRINT_OUTCOME based on this
  # issue's outcome (any non-success → sprint failed).
  rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$ISSUE_NUM"

  # Release the claim based on per-issue LAND_OUTCOME (round 2 re-anchor, R2.3).
  # Hold on `created` because the PR is in flight on the remote;
  # releasing would let a concurrent pipeline open a duplicate PR. TTL will
  # sweep if CI stalls (claim_ttl_seconds default 7200).
  # `monitored` is NOT a reachable LAND_OUTCOME value (it is a STATUS that
  # falls through to the CI_STATUS case where LAND_OUTCOME resolves to one
  # of {merged, pr-ready, created, pr-ci-failing}); it would be dead code
  # if listed in the case, so it is intentionally absent. (DA3.1.)
  case "$LAND_OUTCOME" in
    merged|pr-ready|pr-ci-failing|rebase-conflict|rebase-failed|push-failed|create-failed|monitor-failed|merge-failed)
      bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" \
        || echo "fix-issues: claim release for #$ISSUE_NUM returned non-zero (continuing)" >&2 ;;
    created)
      echo "fix-issues: holding claim for #$ISSUE_NUM (LAND_OUTCOME=created — PR is in flight); TTL=${ZSKILLS_CLAIM_TTL_SECONDS:-7200}s will sweep if PR stalls" >&2 ;;
    *)
      echo "fix-issues: unknown LAND_OUTCOME=$LAND_OUTCOME for #$ISSUE_NUM; defaulting to HOLD (TTL will sweep)" >&2 ;;
  esac

  case "$LAND_OUTCOME" in
    merged|created|pr-ready) ;;  # success-equivalent; sprint outcome unchanged
    *) SPRINT_OUTCOME=failed ;;
  esac
  ```
  Default-to-HOLD on unknown LAND_OUTCOME is the conservative choice. The 10 reachable `LAND_OUTCOME` values are: `merged`, `created`, `pr-ready`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed` (verified via `grep -n 'LAND_OUTCOME=' modes/pr.md` showing assignments at lines 93/146/184/188/196/198/202/205/210/269/273; `__init__` is the initial sentinel; **`monitored` is NOT reachable** — it's a STATUS value that falls through to `case "$CI_STATUS"` and resolves to one of {`merged`, `pr-ready`, `created`, `pr-ci-failing`}, per DA3.1). (R3/DA1/R2.3/DA3.1.)
- [ ] **W2.6b** — Release in cherry-pick mode. **File: `skills/fix-issues/modes/cherry-pick.md`**. Cherry-pick mode does NOT call `/land-pr` per-issue — it cherry-picks worktree commits onto main directly, iterating worktrees in PROSE (no fenced `for` loop). Release sites — **round 2 re-anchor (R2.2):** the canonical per-worktree terminal actions are the `.landed`-write blocks at step 5b (`status: full`, ~modes/cherry-pick.md:60-78) and step 5c (`status: partial`, ~modes/cherry-pick.md:80-92). NOT step 6/7 (those are `git commit .claude/logs/` and `git stash pop`, sprint-wide not per-worktree).
  - **On successful cherry-pick** (step 5b, after `write-landed.sh` returns) — release the claim for that issue.
  - **On cherry-pick conflict** (step 5c, after the partial `.landed` write) — release the claim.
  Implementation: add a `bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true` line inside each per-worktree terminal prose block at step 5b and step 5c (the prose says "for each worktree whose commits were successfully cherry-picked" — the release call lives inside that per-worktree action alongside the `.landed` write). **Design note:** cherry-pick.md's prose-iterated structure means an implementer reading these instructions must add the line inside the prose-described per-worktree action, NOT inside a fenced `for` loop — there isn't one. A future cleanup could materialise the per-worktree iteration as a fenced bash `for` loop (out of scope for this plan). (R3/DA1/R2.2.)
- [ ] **W2.6c** — Release in direct mode. **File: `skills/fix-issues/modes/direct.md`**. Direct mode FF-merges per-issue. **Round 3 correction (DA3.3):** four IMPLEMENTED terminal arms (down from round 2's five — `direct-verify-failed` is a code-comment placeholder, not a real terminal):
  - **`status: full` — successful FF-merge** (~modes/direct.md:130-139, end of per-issue success arm — the `cat <<LANDED` ending at line 139 with `continue` semantically at end-of-iteration).
  - **`status: conflict` — rebase-conflict** (~modes/direct.md:64-73, where `git rebase` fails; `continue` at line 73).
  - **`status: conflict` — FF-refused** (~modes/direct.md:92-101, where the FF-merge is refused; `continue` at line 101).
  - **`status: direct-push-failed` — push-failed** (~modes/direct.md:111-120, where `git push origin main` fails; `continue` at line 120).
  - **`status: direct-verify-failed` — ASPIRATIONAL (DA3.3).** modes/direct.md:80 contains only a code-comment placeholder: `# Re-verification has its own fix cycle (max 2 attempts). If it fails / after max attempts, write status: direct-verify-failed and continue.` The actual dispatch + write-landed-marker for this terminal is NOT IMPLEMENTED in the current codebase. **Implementation:** the release wiring for `direct-verify-failed` is documented here for the future implementer — when the re-verify fix-cycle terminal is wired up as real code, the release call MUST be added alongside the new `cat <<LANDED ... status: direct-verify-failed ...` block. **Mark in the plan diff** with an inline `<!-- aspirational: implement when direct-verify-failed terminal lands -->` HTML comment in `modes/direct.md` adjacent to the line-80 placeholder so a future grep finds the integration site. Do NOT add a release call at line 80 today — there's no terminal to release after.
  Implementation: at each of the four IMPLEMENTED terminal `continue` arms in the per-issue loop body, add `bash "$HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true` immediately before the `continue` / end-of-loop-iteration. (R3/DA1/DA2.6/DA3.3.)
- [ ] **W2.7** — Bump `metadata.version` on `skills/fix-issues/SKILL.md` using `bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$(TZ=America/New_York date +%Y.%m.%d)+$(bash scripts/skill-content-hash.sh fix-issues)"`. Mirror via `bash scripts/mirror-skill.sh fix-issues`. **Important**: `skill-content-hash.sh` recurses the skill directory and INCLUDES `modes/*.md` and `scripts/*.sh` in its hash input (verified by reading the script body), so the W2.6a/b/c mode-file edits and the new claim scripts ARE reflected in the new hash. No separate mode-file version field exists; the SKILL.md version covers the whole skill subtree.

### Design & Constraints

- **W2.0 is the load-bearing anchor for W2.2.** Without explicit `TO_DISPATCH=(...)` materialisation, the acquire loop iterates a non-existent array (empty under `set -u`, undefined behaviour under bash defaults). W2.0 promotes the orchestrator's prose-built picked list into a concrete fenced array via the `PICKS: <numbers>` structured-output contract (DA2.4). **Round 2 anchor (R2.1):** W2.0 sits BETWEEN the no-actionable `exit 0` at SKILL.md:1923 and the partial-dispatch trim's `LIVE_COUNT=` at SKILL.md:2022 — so the no-actionable branch never materialises `TO_DISPATCH`, and the trim consumes it as it always has.
- **W2.2 placement: acquire AFTER trim (round 2 reorder, R2.1/DA2.5).** Acquire MUST run AFTER the partial-dispatch trim has reduced `TO_DISPATCH` to the kept prefix. This simplifies the plan substantially: no release-on-trimmed-suffix path (the suffix is already dropped before acquire), no release-on-SLOTS<=0 path (that arm exits before acquire), no chip-flicker race between acquire and trim (mkdir/rmdir round-trips don't fire on issues that will be dropped). The previous plan had acquire-before-trim with W2.3 + W2.4 release paths to compensate; those work items are deleted in round 2 because the reorder makes them unnecessary.
- **W2.6 is split across THREE files** (`modes/pr.md`, `modes/cherry-pick.md`, `modes/direct.md`) — verified by `grep -n "case.*STATUS" modes/*.md` showing only `pr.md:175`; cherry-pick + direct don't dispatch `/land-pr` per-issue at all. (R3/DA1.) Cherry-pick + direct mode releases happen at per-issue success/failure terminal arms, not at a STATUS case.
- **W2.6a release table MUST be exhaustive over the 10 reachable `LAND_OUTCOME` values** (`merged`, `created`, `pr-ready`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed`). **`monitored` is excluded** — it is a STATUS value, not a LAND_OUTCOME value, and including it in the HOLD arm would be dead code (DA3.1). The unknown-LAND_OUTCOME fallback is HOLD — conservatively preserving claim integrity. (R2.3 corrected the keying from `$STATUS` to `$LAND_OUTCOME`; DA3.1 corrected the count from 11 to 10 by removing the unreachable `monitored`.)
- **W2.5.5 preserves sprint-abort semantics on create-worktree failure (R2.4).** The existing `exit "$RC"` at SKILL.md:2176-2179 is a cross-cutting behaviour (used by all `/fix-issues` users, not just claim-mode). Changing it to `continue` would be a behaviour shift requiring its own design surface; instead, the plan releases the in-flight claims (failing issue's claim + not-yet-dispatched suffix) on the abort path, then `exit "$RC"` as today. This means a single bad issue still aborts the whole sprint — consistent with current behaviour — but the held claims are cleaned up rather than leaking until TTL.
- **All bash fences referencing resolved config MUST source `zskills-resolve-config.sh` at the fence top.** Same for `claim-fence-helpers.sh`. The deny-list test at `tests/test-skill-conformance.sh` fence-local check fails closed.
- **No `2>/dev/null` on fallible ops.** The `|| true` on `claim-issue.sh sweep` (W2.1) is allowed because sweep is best-effort hygiene with no semantic impact on the sprint outcome; document this in a comment immediately above the line. Same justification for `|| true` on per-issue release calls when STATUS is already-failed (idempotent-on-absent semantics make release-after-release a no-op).
- **Tracking-marker discipline:** claims live under `.zskills/claims/`, NOT `.zskills/tracking/`. Do not add any `requires.*` / `fulfilled.*` / `step.*` markers from this phase.
- **The "Dashboard Ready is empty" branch at `SKILL.md:1410-1414` is unchanged.** Empty-Ready-from-state-file routes through `ship_sync_only_or_cleanup` as today. The new "all claimed by concurrent pipelines" exit added in W2.2 routes through the SAME helper with a different stderr message — preserves the existing PR-shipping behaviour for the sync-only commit that Phase 1a may have produced.
- **Phase 2 LOC estimate:** ~80 LOC across SKILL.md + 3 mode files for the fences + release-call additions; ~450 LOC tests. Total Phase 2: ~530 LOC. Phase 1: claim-issue.sh ~300 + claim-fence-helpers.sh ~60 + Phase 1 tests ~250 = ~610. Phase 3: ~130. Phase 4: ~600. Plan total ~1900 LOC — above the original "600-1000" estimate; reflected here as the honest cost. (DA14.)

### Tests

- [ ] **T2.1** — `tests/test-fix-issues-claim-acquire.sh`: stub the upstream `OPEN_NUMS` and `monitor-state.json` so Phase 2 builds a known `TO_DISPATCH`. **Source `claim-fence-helpers.sh` directly** (not a bash-c re-extraction; per DA15 the library exists precisely for testability). Pre-claim one of the issues from a "concurrent pipeline" via direct `claim-issue.sh acquire` call. Call `acquire_for_dispatch_list "test-pipeline" "test-sprint"` and assert that issue is dropped from the final dispatch list with the documented stderr line. Also assert that acquire is invoked ONCE PER kept-prefix issue (not on trimmed-suffix issues) — verifies the round-2 acquire-after-trim ordering. **All-fits-path coverage (DA3.2):** add a separate test scenario where `SLOTS >= N_REQUESTED` (the implicit-else branch — no trim fires) and assert acquire IS invoked for every issue in `TO_DISPATCH`. Without this assertion, an implementer who mis-anchored W2.2 inside the `elif` body (so acquire fires only on partial-trim) would still pass the partial-trim-path test. The two scenarios together gate that the acquire fence lives AFTER the closing `fi`, not inside the elif body. Concretely, drive the test with `TO_DISPATCH=(101 102)`, `SLOTS=3` (so no trim) and assert claim dirs exist for both 101 and 102 post-call.
- [ ] **T2.2** — `tests/test-fix-issues-claim-release-pr.sh`: parameterised over the 10 reachable `LAND_OUTCOME` values from `modes/pr.md` — `merged`, `created`, `pr-ready`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed` (R2.3 — keying corrected from `$STATUS` to `$LAND_OUTCOME`; DA3.1 — `monitored` removed as unreachable). For each, set up a held claim, drive the W2.6a release/HOLD logic (via a small extracted shell function or by sourcing the fence body), assert release-or-HOLD per the D3 PR-mode row. **Negative assertion (DA3.1):** add a `monitored`-as-LAND_OUTCOME case parameterised in to assert it routes to the default/HOLD arm (because `monitored` is not in the explicit case list) — confirms an implementer who accidentally typed `monitored` into the case wouldn't silently match an unreachable value. Comment in the test: `# DA3.1 guard: monitored is a STATUS not LAND_OUTCOME; if it ever reaches here it must fall to HOLD default.`
- [ ] **T2.2b** — `tests/test-fix-issues-claim-release-cherry-pick.sh`: simulate the step-5b `.landed status: full` path and the step-5c `.landed status: partial` path; assert claim released in both arms (R2.2).
- [ ] **T2.2c** — `tests/test-fix-issues-claim-release-direct.sh`: simulate the four IMPLEMENTED terminal arms (`status: full`, `status: conflict` rebase-conflict, `status: conflict` FF-refused, `status: direct-push-failed`); assert claim released in each (DA2.6/DA3.3). **`direct-verify-failed` is NOT tested here** because the terminal is currently a code-comment placeholder at modes/direct.md:80 with no real dispatch/write. When that terminal lands as real code, the implementer of that future PR must extend this test with the fifth case as part of the same diff (tracked via the `<!-- aspirational -->` marker W2.6c places at the line-80 site).
- [ ] **T2.3** — Unit test for the unknown-LAND_OUTCOME fallback (PR mode only): pass `LAND_OUTCOME=garbage`, assert HOLD + stderr warning.
- [ ] **T2.4** — Unit test for worktree-add failure release (W2.5.5/R2.4): simulate `create-worktree.sh` returning non-zero for one issue mid-`TO_DISPATCH`; assert (a) that issue's claim is released, (b) the NOT-yet-dispatched suffix's claims are released, (c) ALREADY-dispatched prefix's claims remain held (those agents are still running), (d) the script exits with the create-worktree RC (sprint-abort preserved).

### Acceptance Criteria

- [ ] All T2.* tests green.
- [ ] `skills/fix-issues/SKILL.md` `metadata.version` bumped and mirror diff empty.
- [ ] `bash tests/test-skill-conformance.sh` green (forbidden-literals + fence-local config sourcing checks).
- [ ] `git diff --stat` for this phase touches only `skills/fix-issues/SKILL.md`, `skills/fix-issues/modes/pr.md`, `skills/fix-issues/modes/cherry-pick.md`, `skills/fix-issues/modes/direct.md`, the corresponding `.claude/skills/fix-issues/` mirrors, and `tests/test-fix-issues-claim-*.sh`. No collateral edits.

### Dependencies

- Phase 1 (claim primitive script and config field must exist).

---

## Phase 3 — Dashboard collector + renderer chip

### Goal

Make claims visible on the dashboard. `collect.py` reads `.zskills/claims/` per snapshot and attaches a `claim` field to each issue dict; `app.js buildIssueCard` renders a non-interactive chip when `claim` is present.

### Work Items

- [ ] **W3.1** — Extend `skills/zskills-dashboard/scripts/zskills_monitor/collect.py`:
  - Add `_read_claims(main_root: pathlib.Path)` as a **module-level private function placed adjacent to `_build_skip_reason_index` (~collect.py:1544 / 1369-area)**, following the sibling-private precedent. (R9.) Required signature: `def _read_claims(main_root: pathlib.Path) -> Dict[int, Dict[str, Any]]:` — `main_root` is REQUIRED, not Optional, because the fixture branch (collect.py:1770) skips the call entirely (see gating rule below). Enumerates `.zskills/claims/issue-*/claim.json` under `main_root`, parses each (tolerant — skip on malformed JSON with a single stderr line), returns `{issue_number: claim_dict_with_age}` where `age = (now - started_at_parsed).total_seconds()`.
  - **Gating rule (R2.6):** the `_read_claims(main_root)` call from `_annotate_issues_queue` MUST be wrapped in `if main_root is not None:` — mirrors the existing skip_index gate pattern at collect.py:1339. The fixture branch (collect.py:1770, 2-arg call without `main_root`) skips claim annotation entirely; T3.1 unit test covers the 3-arg branch with a mocked filesystem. Implementer: do NOT call `_read_claims` unconditionally; the fixture branch lacks a real `.zskills/claims/` directory and the call would either crash on `NoneType` or no-op pointlessly.
  - Modify `_annotate_issues_queue` (line 1312): after building the `pos` lookup AND `skip_index`, **gated on `main_root is not None`,** lookup each issue's number in the claims dict; if found, set `issue["claim"] = {pipeline_id, sprint_id, age_seconds, started_at, pipeline_short}`. **DO NOT include `host_pid` (no longer in claim.json per DA2.1/DA2.2) or `worktree_path` (never in claim per DA8).** Use explicit field allow-list, not `**claim_dict`, to prevent future-added fields leaking accidentally.
  - **`pipeline_short` rendering (DA4):** the slice `pipeline_id.split(".")[-1][:8]` produces useless `"sprint-2"` for every concurrent sprint (the `sprint-YYYYMMDD-` prefix dominates the first 8 chars). Instead, derive `pipeline_short` from the time+slug tail: `sprint_id_tail = pipeline_id.rsplit(".", 1)[-1]  # e.g. "sprint-20260521-010731-foo"; parts = sprint_id_tail.split("-"); pipeline_short = "-".join(parts[2:4]) if len(parts) >= 4 else sprint_id_tail[-8:]` — yields `"010731-foo"` for `fix-issues.sprint-20260521-010731-foo`, distinguishing concurrent sprints at a glance. Lock with an explicit rendered example in the test fixture. (DA4.)
  - Tolerant-read discipline: if `claim.json` is missing inside an existing `.zskills/claims/issue-<N>/` directory, treat as "in flight, metadata pending" — surface `{age_seconds: null, pipeline_id: null, pipeline_short: null, started_at: null}` so the chip can render a generic "in-flight" indicator. Avoids the sweep-while-flush race.
  - **Fixture-mode (`collect.py:1770`) keeps its two-arg call** (no `main_root` passed) — fixtures don't need real claim files; T3.1 mocks `_read_claims` directly via a fixture filesystem. Full end-to-end fixture support for claims is out of scope. (DA13.)
- [ ] **W3.2** — Extend `skills/zskills-dashboard/scripts/zskills_monitor/static/app.js`:
  - In `buildIssueCard` (~line 845), after the `skip_reason` chip block (lines 872-884), add an analogous `claim` chip. **Reuse the existing `relativeTime` helper at `app.js:97`** — DO NOT introduce a parallel `formatAge`. (R8.) `relativeTime` accepts an ISO-8601 string (verified usage at lines 312, 811, 864) but **returns the empty string `""` on falsy or unparseable input** (verified at `app.js:98-100`); the chip text composer MUST coalesce empty `relativeTime` output to a `"?"` fallback so the chip never renders with a trailing dot-space-empty (R2.7):
    ```js
    if (issue && issue.claim) {
      const c = issue.claim;
      const rt = c.started_at ? relativeTime(c.started_at) : "";
      const ageStr = rt || "?";  // R2.7: relativeTime returns "" on bad input
      const pidShort = c.pipeline_short || "?";
      const tip = c.pipeline_id
        ? `claim pipeline=${c.pipeline_id} started=${c.started_at}`
        : "claim metadata pending";
      const row = el("div", { cls: "card-sub" });
      row.appendChild(el("span", {
        cls: "claim-chip claim-chip--in-flight",
        attrs: { title: tip },
        text: `in-flight · ${pidShort} · ${ageStr}`,
      }));
      card.appendChild(row);
      // Disable drag while claimed — the card represents work another pipeline
      // is acting on; allowing drag-reorder mid-flight invites a ghost-claim
      // footgun. (DA11.) Note: this is the DRAG defense only — keyboard move
      // and remove buttons are guarded separately at the action dispatcher
      // (see below; DA2.3).
      card.setAttribute("aria-disabled", "true");
      card.removeAttribute("draggable");
    }
    ```
  - **Guard the action dispatcher at app.js:1806-1810 (DA2.3).** Drag-disable alone is cosmetic — `buildIssueCard` unconditionally appends four keyboard move buttons (`issue-up/down/left/right`) and a remove button (`issue-remove`) at app.js:892-909. Their click handlers at app.js:1806-1810 invoke `moveIssue()` / `removeIssue()` without any claim/aria-disabled check, so a user can mutate a claimed card's position OR delete it via keyboard or pointer click. Add a guard immediately above the existing `if (action === "issue-up")` line:
    ```js
    // Guard: claimed issues are in-flight on another pipeline. Block move
    // and remove actions to prevent ghost-claim footgun (DA2.3 / DA11).
    if (action === "issue-up" || action === "issue-down" ||
        action === "issue-left" || action === "issue-right" ||
        action === "issue-remove") {
      const claimedCard = target.closest('li.card[aria-disabled="true"][data-kind="issue"]');
      if (claimedCard) {
        showToast("Issue is in-flight; release the claim or wait for completion.", "info");
        return;
      }
    }
    if (action === "issue-up") return moveIssue(num, "up");
    // ... existing handlers ...
    ```
    Also audit the equivalent keyboard-shortcut handler (search for `moveIssue\|removeIssue` references in app.js to find any non-click dispatch sites) — if found, apply the same `aria-disabled` check. T3.2 below verifies all five action types are blocked on claimed cards.
  - Add CSS class `.claim-chip--in-flight` to `static/app.css` — distinct background colour (suggest a soft amber `#fff3d6` with `#7a5a00` text — visually distinct from skip-reason chip's coloring; verify by reading current `.skip-chip` rules and picking a different hue). Add `.card[aria-disabled="true"] { cursor: not-allowed; opacity: 0.85; }` to visually signal the drag-disabled state.
  - **Extend `fingerprintIssues` (app.js:484) to include claim state** — `JSON.stringify(issues.map(i => [i.number, i.title, ..., i.claim ? [i.claim.pipeline_id || null, i.claim.started_at || null] : null]))`. Without this, the snapshot fingerprint is byte-identical between "no claim" and "claim present" states (`fingerprintIssues` covers only `[number, title, labels, created_at, [column, index]]`), so `applySnapshot` skips `renderIssues` and the chip never appears/disappears between polls. (DA5.) Add a regression test asserting `fingerprintIssues` output differs across (claim-absent, claim-pending, claim-present) shapes.
- [ ] **W3.3** — Bump `metadata.version` on `skills/zskills-dashboard/SKILL.md` (collect.py, app.js, app.css are content-hash inputs). Mirror.
- [ ] **W3.4** — Update server-side validation IF needed. The validator at `server.py:475-491` validates POSTed `monitor-state.json` writes only; the `claim` field is server-derived in the GET response and not part of any POST contract. Confirm by reading the validator. If correct, NO server.py change is required for this plan. Document the confirmation in the phase report.

### Design & Constraints

- **`collect.py:_read_claims` runs on every snapshot.** Concern: latency. Reading 5-50 small JSON files per snapshot is `O(claims_count)` and bounded by `execution.max_concurrent_worktrees` (default 3). The latency budget is the open `issues_fetch_ok` 60s cache window — claim reads are not cached because they change on the second. **Lock budget: <10ms wall-clock p99 for 50 simulated claims** (well below `/api/state`'s current 6s baseline per issue #514, so claim reads add <1% to existing latency). T3.4 below gates this with a benchmark test that fails if exceeded; if exceeded, memoize per-snapshot identically to `issues_fetch_ok`. (DA6.)
- **Future-field leakage protection:** the collector copies claim fields via an explicit allow-list (`pipeline_id`, `sprint_id`, `age_seconds`, `started_at`, `pipeline_short`), NOT via `**claim_dict`. This prevents any future-added claim field from leaking into the HTTP response automatically; if a new field needs to be exposed it must be added to the allow-list deliberately. (Historical: round 1 worried specifically about `host_pid` leakage — round 2 removed that field entirely per DA2.1/DA2.2, so the concern is now vacuous, but the allow-list discipline remains for future-fields.)
- **No-server-py-change is load-bearing.** The collector is read-only over `.zskills/claims/`; the server's validator only fires on POST bodies. If a reviewer asks "why no server.py edit," point to this. The `monitor-state.json` schema is unchanged per D7.
- **Reuse `relativeTime`, not new `formatAge`.** The existing helper at `app.js:97` is used at lines 312/811/864/1016/1032/1088 — reusing it is consistent with the rest of the dashboard's time rendering. (R8.)
- **CSS class naming (W3.2) follows existing convention** `<entity>-chip <entity>-chip--<variant>` per the skip-reason precedent.

### Tests

- [ ] **T3.1** — `tests/test-fix-issues-claim-collector.py` (pytest-compatible; use stdlib `unittest` if pytest is not available — confirm by `grep -r 'import pytest'` in `tests/`): mock filesystem with three `.zskills/claims/issue-{1,2,3}/claim.json` files (one fresh, one mid-age, one with absent `claim.json` inside directory). Run `_read_claims` and `_annotate_issues_queue`. Assert: claim field populated for issues 1+2; null-metadata claim for issue 3; `pipeline_short` derivation correct — specifically assert `pipeline_short == "010731-foo"` for `pipeline_id == "fix-issues.sprint-20260521-010731-foo"` (DA4 explicit-example lock); assert NO `host_pid` (claim no longer carries it per DA2.1/DA2.2), NO `worktree_path` (DA8) in any claim dict. **Fixture-branch gate (R2.6):** assert that calling `_annotate_issues_queue` from the 2-arg fixture path (without `main_root`) does NOT call `_read_claims` (mock the function and assert call count == 0).
- [ ] **T3.2** — `tests/test-fix-issues-claim-render-dom.sh` (or extend `tests/e2e-monitor-server.sh` if that's the existing precedent): spin up the dashboard against a fixture with claims; HTTP GET `/api/state`; assert response includes `claim` field on the relevant issues; assert the rendered HTML (via `curl` + grep on the SSR or via headless playwright-cli if the project's UI tests use that) contains `claim-chip--in-flight` for each claimed issue. Also assert the claimed card has `aria-disabled="true"` and lacks `draggable="true"` (DA11). **Action-dispatch guard (DA2.3):** simulate click events on each of the five action buttons (`issue-up`, `issue-down`, `issue-left`, `issue-right`, `issue-remove`) on a CLAIMED card; assert that `moveIssue` and `removeIssue` are NOT called (mock the API call layer and assert call count == 0 across all five); assert a toast appears with the documented "Issue is in-flight" message. Repeat on an UNCLAIMED card and assert the handlers ARE called (negative control). **Chip-text fallback (R2.7):** render a claim with `started_at` parsable but very old (e.g. Date.parse returns NaN edge case via a malformed-but-non-empty string); assert the chip text is `"in-flight · 010731-foo · ?"`, NOT `"in-flight · 010731-foo · "` (no trailing empty). **`fingerprintIssues` regression assertion**: render three snapshots — issue 5 with no claim, issue 5 with pending-claim, issue 5 with full claim. Compute `fingerprintIssues` for each; assert all three strings differ. (DA5.)
- [ ] **T3.3** — Latency benchmark **gating** test: on a host with 50 simulated claims, run `_read_claims` 100 times; assert wall-clock p99 <10ms. Fail-on-regress. **NOT skip-not-fail** — this is the budget lock from DA6. Test name references issue #514 in a header comment so future contributors know the rationale.

### Acceptance Criteria

- [ ] All T3.* tests green.
- [ ] `skills/zskills-dashboard/SKILL.md` `metadata.version` bumped and mirror diff empty.
- [ ] `server.py` is unchanged in this phase's diff (confirms D7).
- [ ] Visual smoke test: with `/zskills-dashboard start`, a fixture claim makes a card render with the in-flight chip; releasing the claim and waiting one poll interval makes the chip disappear. Screenshot attached to PR body.

### Dependencies

- Phase 1 (`claim.json` schema must be stable before the collector parses it).
- Phase 2 RECOMMENDED — Phase 3 can technically begin in parallel with Phase 2, but T3.2's full integration check uses claim files that look like real-pipeline output. If Phase 2 hasn't landed yet, T3.2 fabricates claim files by hand (acceptable for unit-grade testing; the true end-to-end signal is Phase 4's W4.1). (R12.)

---

## Phase 4 — E2E concurrency test + conformance + integration

### Goal

Prove the cross-cutting promise: two concurrent `/fix-issues 1 dashboard auto` runs pick distinct issues. Add the conformance assertions and the regression test that single-pipeline behaviour is unchanged.

### Work Items

- [ ] **W4.1** — `tests/test-fix-issues-claim-race-e2e.sh`. Lift the scaffolding from `tests/e2e-parallel-pipelines.sh` (per the prior-art agent's note). Setup: fixture repo with 3 mocked open issues queued in `issues.ready`. Two backgrounded subshells each **source `claim-fence-helpers.sh` and call `acquire_for_dispatch_list "pipeline-A" "sprint-A"` / `pipeline-B` / `sprint-B`** — using the same library Phase 2 fences use (per DA15). NOT a full `/fix-issues` run — too slow for CI. Wait for both via `wait`. Capture each subshell's stdout/stderr to separate temp files. Assert: exactly two claims exist on disk; the picked issue numbers are distinct; no shared worktree branch name was attempted.
- [ ] **W4.1b** — **Negative-control / baseline race test** (DA7, CLAUDE.md "surface bugs don't patch"): `tests/test-fix-issues-claim-race-baseline.sh`. Same shape as W4.1, but with `claim-issue.sh acquire` STUBBED to a no-op that always returns 0. Assert BOTH pipelines pick the SAME issue (the original bug). Paired with W4.1 this proves (a) the race actually exists without the mechanism, and (b) the mechanism prevents it. If a future refactor accidentally bypasses the acquire call, W4.1b stays passing — but if it removes acquire entirely, W4.1 fails and W4.1b proves the regression matters.
- [ ] **W4.2** — `tests/test-fix-issues-claim-conformance.sh`. Assertions:
  - `claim-issue.sh` and `claim-fence-helpers.sh` exist under both `skills/fix-issues/scripts/` and `.claude/skills/fix-issues/scripts/` (mirror).
  - `claim-issue.sh acquire 0` rejects (non-positive integer guard).
  - `claim-issue.sh acquire abc` rejects (non-numeric guard).
  - **NO inline `rm -r|rf|--recursive` against `.zskills/claims/`** in `skills/fix-issues/SKILL.md`, `skills/fix-issues/modes/*.md`, or any test file outside `claim-issue.sh` itself — grep-asserts zero hits for the regex `\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)[[:space:]]+[^;&|]*\.zskills/claims`. (R2/R5/DA3.)
  - Run `hooks/block-unsafe-project.sh.template` against a fake Bash tool call payload `bash claim-issue.sh release 42 --require-pipeline X` and assert ALLOW (the script invocation is not a destructive command at the hook layer).
  - Run `hooks/block-unsafe-project.sh.template` against a fake Bash tool call payload `rm -rf .zskills/claims/issue-42` and assert BLOCK (negative control — protects the invariant that inline forms remain hook-blocked).
  - `.zskills/claims/` is gitignored (likely already covered by `.zskills/` blanket — confirm and document).
- [ ] **W4.3** — `tests/test-fix-issues-claim-regression-single.sh`. **Round 3 fix (DA3.4):** earlier draft said "run `/fix-issues 3 dashboard auto` against a stub repo" — that's unrunnable from a bash test because `/fix-issues` is an agent-driven slash command, not a shell entry point. `bash tests/run-all.sh` cannot dispatch slash commands. **Restructured test:** verify the underlying mechanism in isolation by sourcing `claim-fence-helpers.sh` and driving `acquire_for_dispatch_list` with a single-pipeline call (no concurrent acquirer), then assert the resulting `TO_DISPATCH` survivor list is byte-identical to the input — i.e. the introduction of `acquire_for_dispatch_list` does not perturb single-pipeline dispatch order. The test ALSO calls `sweep_stale_claims` on a no-claims directory and asserts it is a no-op. Together these gate A7 ("single-pipeline `dashboard` mode behaviour is byte-for-byte identical to today when only one `/fix-issues` is running") at the mechanism layer that the bash test can actually exercise. A golden-file diff against a recorded baseline is unnecessary because the mechanism is direct identity-of-input-list when no contention exists. **Full end-to-end `/fix-issues 3 dashboard auto` regression** is moved to PR test plan as a MANUAL repro step (orchestrator-driven, single-shot, screenshot attached to PR body — see Phase 4 Acceptance Criteria) — NOT a `tests/run-all.sh` suite member. This protects A7 at both the mechanism layer (automated) and the integration layer (manual PR-time check).
- [ ] **W4.4** — Verify the existing `tests/test-skill-conformance.sh` passes — no new forbidden literals, no fence-local config-sourcing miss. Run `bash tests/run-all.sh` end-to-end and capture the output per the canonical idiom (`TEST_OUT=/tmp/zskills-tests/$(basename "$(pwd)") ...`). **Important: `tests/run-all.sh` uses an explicit `run_suite` list (NOT a glob)** — verified by reading the script. Phase 4 MUST add all new test scripts to this list. (R10.) The required additions: `test-fix-issues-claim-script.sh`, `test-fix-issues-claim-acquire.sh`, `test-fix-issues-claim-release-pr.sh`, `test-fix-issues-claim-release-cherry-pick.sh`, `test-fix-issues-claim-release-direct.sh`, `test-fix-issues-claim-collector.py` (wrap in a `.sh` shim that invokes pytest/unittest), `test-fix-issues-claim-render-dom.sh`, `test-fix-issues-claim-race-e2e.sh`, `test-fix-issues-claim-race-baseline.sh`, `test-fix-issues-claim-conformance.sh`, `test-fix-issues-claim-regression-single.sh`.
- [ ] **W4.5** — `/cleanup-merged` integration (R11). `skills/cleanup-merged/SKILL.md` currently doesn't sweep `.zskills/claims/` — when a PR merges externally (web UI / manual gh merge) bypassing `/land-pr`'s STATUS=merged release path, the claim leaks until TTL. Add a single-line invocation `bash .claude/skills/fix-issues/scripts/claim-issue.sh sweep || true` to `/cleanup-merged` after the worktree-pruning step. Bump `skills/cleanup-merged/SKILL.md` `metadata.version`. Mirror.
- [ ] **W4.6** — Document the claim mechanism in `skills/fix-issues/SKILL.md` near the top of the dashboard-mode section: a short prose paragraph pointing readers at `claim-issue.sh` and the D1-D6 decisions. Also update the agent-facing `README.md` if it has a section on `dashboard` mode. Do NOT add a separate dashboard `README` — the chip's tooltip carries the operational detail.

### Design & Constraints

- **The E2E race test (W4.1) is the load-bearing concurrency proof.** It MUST use real shell processes (not Python `threading`) — that's the only way to verify cross-process atomicity. Run with `&` and `wait`; capture stdout/stderr of each to separate temp files; inspect after.
- **The regression test (W4.3) gates A7.** If the golden file differs, that's either a real regression or a need to regenerate the golden — the implementer must NOT regenerate without inspecting the diff manually.
- **All four test scripts MUST capture output to `$TEST_OUT/.test-results.txt`** per CLAUDE.md ("Capture test output to a file, never pipe").
- **`bash tests/run-all.sh` green** before commit. No skips, no `// #NNN` deferrals on new tests.

### Tests

(This phase IS the tests phase; the work items above are the tests themselves.)

### Acceptance Criteria

- [ ] All T2.*, T3.*, and W4.1-W4.5 tests green individually (including W4.1b baseline race test).
- [ ] `bash tests/run-all.sh` green end-to-end with all new test scripts added to the explicit `run_suite` list.
- [ ] `bash tests/test-skill-conformance.sh` green.
- [ ] `git diff --stat HEAD~4..HEAD` shows changes only to documented files (no surprise edits).
- [ ] `skills/cleanup-merged/SKILL.md` `metadata.version` bumped per W4.5; mirror diff empty.
- [ ] Manual two-terminal repro: open two terminals, run `/fix-issues 1 dashboard auto` in each within 2 seconds of one another; capture screenshot of the dashboard showing two in-flight chips on two different issues with distinct `pipeline_short` values; attach to PR body.
- [ ] **Manual single-pipeline regression repro (A7 integration-layer check per DA3.4):** in a stub fixture repo with 3 mocked open issues, run `/fix-issues 3 dashboard auto` ONCE; record the picked issue numbers and dispatch order; verify they match what a pre-claim-mechanism `/fix-issues` run would have picked (e.g. priority-ranked head-of-queue). Attach the captured selection log to PR body. The automated W4.3 test gates the mechanism layer; this manual repro gates the integration layer.

### Dependencies

- Phases 1, 2, 3 complete.

---

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (reviewer + devil's-advocate + refiner). Rounds executed and converged in round 3.

**Convergence:** Round 3 surfaced 1 critical + 3 major + 1 minor finding; all 5 verified against repo evidence (SKILL.md anchor lines, mode-file LAND_OUTCOME assignments, direct.md placeholder comment) and fixed in place. No new gaps surfaced during round 3 refinement. Plan is FINAL.

**Remaining concerns:** None of blocker or major grade. Two areas the implementer should watch:

- **`direct-verify-failed` is aspirational (DA3.3).** W2.6c documents the future integration site at modes/direct.md:80 via an inline `<!-- aspirational -->` HTML comment so a future implementer wiring the real terminal can find it. T2.2c does NOT test this case; when the terminal is implemented, that PR must extend T2.2c.
- **`PICKS: <numbers>` structured-output contract (DA2.4).** W2.0 introduces a new orchestrator-narrative-to-bash-fence contract. This is the only place in the plan where a model-built value gets substituted into a fence. If the triage prose stops emitting the `PICKS:` line (e.g. a future SKILL.md edit), the W2.0 fence will execute with an empty placeholder. Conformance discipline: add an explicit verification step in W2.0 instructions reminding the implementer to grep `modes/pr.md`/SKILL.md for `PICKS:` in any future related edit.

### Round History

| Round | Reviewer findings | DA findings | Verified-and-fixed | Justified-not-fixed | New gaps |
|-------|-------------------|-------------|---------------------|----------------------|----------|
| 1     | 12 (R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12) | 15 (DA1-DA15) | 25 | 2 (DA12, R12 — both minor) | 0 |
| 2     | 7 (R2.1-R2.7)     | 7 (DA2.1-DA2.7) | 14 | 0 | 0 |
| 3     | 2 (R3 reviewer F1+F2) | 4 (DA3.1-DA3.4) | 5 (after dedup of F1↔DA3.1) | 0 | 0 |

**Convergence test:** round 3 verified 5 unique findings against repo source code and fixed each at the work-item or test level. No new bugs introduced. No defer-to-follow-up. Plan ready for `/run-plan`.

## Round 1 disposition summary

**Materially changed sections (review focus for round 2):**

- **D1 (claim storage)** — removed `worktree_path` field per DA8; claim.json now schema = `{schema_version, pipeline_id, sprint_id, issue, started_at, host_pid}`.
- **D2 (acquire site)** — added explicit acknowledgement that `TO_DISPATCH` has no fenced assignment site today; Phase 2 W2.0 introduces one. (R1/DA2.)
- **D3 (release table)** — split per-landing-mode (PR/cherry-pick/direct) because cherry-pick and direct modes don't dispatch `/land-pr` per-issue; added worktree-add failure as a new release path. (R3/DA1/R4.)
- **D4 (TTL)** — added `host_pid` liveness fast-path (`kill -0`) + 30s metadata-window stale rule. (DA9/R7.)
- **D6 (chip)** — added drag-disable while claimed. (DA11.)
- **Phase 1 W1.1** — `release` is per-file removal (mandatory, not fallback); atomic claim.json write via tmp+rename; `is-stale` adds PID liveness + 30s-orphan-dir rule. (R2/R7/DA3.)
- **Phase 1 W1.2.5 (NEW)** — `claim-fence-helpers.sh` library extracted for test/runtime fence parity. (DA15.)
- **Phase 1 W1.4** — switched TTL resolver to a Python one-liner (more robust than BASH_REMATCH on pretty-printed nested JSON). (R6.)
- **Phase 2 W2.0 (NEW)** — explicit `TO_DISPATCH=(...)` materialisation fence. (R1/DA2.)
- **Phase 2 W2.5.5 (NEW)** — release on per-issue worktree-add failure. (R4.)
- **Phase 2 W2.6 split** into W2.6a (modes/pr.md), W2.6b (modes/cherry-pick.md), W2.6c (modes/direct.md). (R3/DA1.)
- **Phase 3 W3.1** — `pipeline_short` derivation rewritten (was producing useless `"sprint-2"`; now produces `"010731-foo"`-style); `worktree_path` removed from HTTP-exposed claim dict. (DA4/DA8.)
- **Phase 3 W3.2** — replaced `formatAge` with reused `relativeTime`; extended `fingerprintIssues` to include claim state (chip would never re-render without this). (R8/DA5.)
- **Phase 3 T3.3** — latency check upgraded from informational to gating (<10ms p99 for 50 claims). (DA6.)
- **Phase 4 W4.1b (NEW)** — baseline race test stubs out `claim-issue.sh acquire` and asserts the race manifests; pairs with W4.1 per CLAUDE.md "surface bugs don't patch." (DA7.)
- **Phase 4 W4.5 (NEW)** — `/cleanup-merged` integration (sweep call). (R11.)
- **Phase 4 W4.4** — pinned that `tests/run-all.sh` uses explicit `run_suite` list (not glob); enumerated the 11 new test files that must be added. (R10.)
- **A6** — rewritten to assert per-file removal and grep-no-inline-rm, not the original (and wrong) "rm -rf is allowed by block-unsafe-generic.sh" claim.
- **LOC estimate** — revised from "600-1000" to ~1900 in the new Phase 2 Design & Constraints budget summary. (DA14.)

**Findings justified-not-fixed:** None of blocker/major grade. Two minor provocations (DA12 mkdir-atomicity on macOS gRPC-FUSE — addressed by a one-line note in "What this plan does NOT do"; R12 Phase 3 dependency on Phase 2 — addressed by amending the Dependencies section without restructuring).

## Round 2 disposition summary

**Materially changed sections (review focus for round 3 if any):**

- **D1 (claim storage)** — removed `host_pid` field per DA2.1/DA2.2. claim.json now schema = `{schema_version, pipeline_id, sprint_id, issue, started_at}`. CLAUDE.md does not document a `kill -0` `2>/dev/null` exception (verified by grep); the orchestrator has no stable PID addressable from the script's ephemeral subshell.
- **D2 (acquire site)** — round 2 reorder per R2.1/DA2.5: acquire runs AFTER the partial-dispatch trim (not before). W2.0 fence re-anchored to between SKILL.md:1923 (no-actionable exit) and SKILL.md:2002 (trim). Eliminates chip-flicker race and wasted mkdir/rmdir round-trips on saturated fires.
- **D3 (release table)** — PR mode re-anchored from `case "$STATUS"` to canonical `case "$LAND_OUTCOME"` block at `modes/pr.md:295-298` (R2.3); cherry-pick anchors corrected to step 5b/5c `.landed`-write sites (R2.2); direct mode expanded from 3 terminals to 5 (added `direct-push-failed` and `direct-verify-failed` per DA2.6); worktree-add failure preserves sprint-abort + releases held suffix (R2.4).
- **D4 (TTL)** — removed PID-liveness fast-path entirely (DA2.1/DA2.2). Relies on TTL + 30s crash-window only. Documented operational consequence: real orchestrator crash → up to 7200s claim persistence before sweep.
- **Phase 1 W1.1** — claim.json schema drops `host_pid`; `is-stale` drops `kill -0` check; `sweep` reason field drops `pid`; added `release-suffix` subcommand for Phase 2 abort path.
- **Phase 1 W1.4** — `PYTHON` renamed to `_ZSK_PYTHON` per R2.5; added to `unset _ZSK_*` end-of-script cleanup.
- **Phase 1 W1.5** — dropped PID-liveness unit test (DA9 obsoleted by DA2.2); added `release-suffix` unit test; sweep stderr reason field updated to `ttl|metadata`.
- **Phase 1 AC** — stripped stale `--worktree /tmp/x` flag from acceptance criterion (DA2.7).
- **Phase 2 W2.0** — re-anchored between SKILL.md:1923 and 2002 (R2.1); added `PICKS: <numbers>` orchestrator structured-output contract for fence substitution (DA2.4).
- **Phase 2 W2.2** — acquire-after-trim reorder (R2.1/DA2.5); operates on the kept prefix only; added trap-based prefix-release on acquire-error-11 mid-loop.
- **Phase 2 W2.3 and W2.4 — DELETED.** Acquire-after-trim makes them unnecessary (no claims to release on the dropped suffix or SLOTS<=0 arm because none were acquired). Net plan simplification: -2 work items.
- **Phase 2 W2.5.5** — preserves existing `exit "$RC"` sprint-abort behaviour (R2.4); releases failing issue's claim AND not-yet-dispatched suffix on the abort path; no cross-cutting behaviour shift.
- **Phase 2 W2.6a** — moved from `case "$STATUS"` at `modes/pr.md:175` to canonical `case "$LAND_OUTCOME"` block at `modes/pr.md:295-298` alongside the existing `requires-marker rm` (R2.3). Release table re-enumerated over 9 `LAND_OUTCOME` values (was incorrectly enumerated over STATUS values).
- **Phase 2 W2.6b** — re-anchored from "step 6/7" to step 5b + step 5c per `modes/cherry-pick.md` actual structure (R2.2); design note added on prose-iterated structure (no `for` loop).
- **Phase 2 W2.6c** — expanded from 3 terminals to 5 (added `direct-push-failed` ~direct.md:112 and `direct-verify-failed` ~direct.md:80 per DA2.6).
- **Phase 3 W3.1** — `_read_claims(main_root)` signature changed to require `main_root` (not Optional); call gated on `if main_root is not None:` per existing skip_index precedent (R2.6).
- **Phase 3 W3.2** — added action-dispatch guard at app.js:1806-1810 to block move/remove on claimed cards (DA2.3 — drag-disable was cosmetic without this guard); chip text coalesces empty `relativeTime` output to `"?"` per R2.7.
- **Phase 3 T3.1** — added fixture-branch gate assertion (R2.6); removed `host_pid` leakage assertion (already covered by "no host_pid in claim.json").
- **Phase 3 T3.2** — added five-button click-guard assertion (DA2.3); added chip-text fallback assertion (R2.7).
- **Phase 2 Design & Constraints** — rewrote the acquire-ordering paragraph; deleted "partial-dispatch trim release is subtle" paragraph (no longer applicable); added sprint-abort-preservation paragraph (R2.4).

## Round 3 disposition summary

**Materially changed sections (FINAL):**

- **W2.2 anchor (DA3.2, CRITICAL)** — re-anchored from "after line 2052" (inside the `elif` body at SKILL.md:2045-2053) to "after the closing `fi` at line 2053". Acquire now fires on BOTH the all-fits-in-slots common case AND the partial-trim case. T2.1 extended with an explicit `SLOTS=3, TO_DISPATCH=(101 102)` all-fits-path scenario asserting acquire is invoked for every issue — gates against future mis-anchoring inside the elif.
- **D3 + W2.6a `monitored` removal (DA3.1 / F1)** — `monitored` is a STATUS value at modes/pr.md:190, NOT a reachable LAND_OUTCOME. The case body in W2.6a's bash fence dropped `monitored` from the HOLD arm (left `created` only). Prose counts corrected from "9 documented" / "11 enumerated" to the actual 10 reachable LAND_OUTCOME values. Added in-fence comment explaining the absence. T2.2 parameterised list reduced to 10 and added a negative-control case asserting `monitored`-as-LAND_OUTCOME falls to the default/HOLD arm (catches any future re-introduction).
- **D3 + W2.6c `direct-verify-failed` is aspirational (DA3.3)** — modes/direct.md:80 is a code-comment placeholder; the terminal is not implemented. W2.6c reduced from 5 to 4 IMPLEMENTED arms; the fifth is documented as aspirational with an `<!-- aspirational -->` HTML-comment marker the implementer drops at line 80 so a future grep finds the integration site. T2.2c tests the 4 implemented arms only. A4 Verification count corrected.
- **W4.3 restructured (DA3.4)** — earlier draft called for "Run /fix-issues 3 dashboard auto" as a bash test — unrunnable because `/fix-issues` is an agent-driven slash command, not a shell entry point. Split into (a) AUTOMATED mechanism-layer test using `claim-fence-helpers.sh` with identity-of-input assertion in the no-contention case, and (b) MANUAL PR-time integration repro added to Phase 4 Acceptance Criteria. A7 Verification rewritten to two-layer.
- **A1 filename consistency (F2, MINOR)** — A1's `tests/test-fix-issues-claim-race.sh` reference corrected to `tests/test-fix-issues-claim-race-e2e.sh` to match W4.1 and W4.4. Prevents phantom third filename creation.
- **Overview + "What this plan does NOT do"** — touched-up `created/monitored` → `created` and `hold-on-monitored` → `hold-on-created-LAND_OUTCOME` terminology to stay consistent with the LAND_OUTCOME / STATUS distinction.

**Findings justified-not-fixed:** None. All 5 unique round-3 findings verified against repo evidence and fixed at the work-item or test level.

**New gaps surfaced:** None.

**Outcome:** Plan is FINAL. Ready for `/run-plan plans/fix-issues-claims.md pr`.
