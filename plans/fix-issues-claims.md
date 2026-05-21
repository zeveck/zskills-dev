---
title: Concurrency-safe issue claims for /fix-issues dashboard mode
created: 2026-05-21
status: complete
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
- **D2 — Acquire site: inline at per-issue dispatch, co-located with `create-worktree.sh` (round 4 — option C).** Round 4 dropped the PICKS-fence-and-loop architecture entirely. Rationale: the original PICKS approach required the orchestrator to emit a structured `PICKS: <numbers>` line which a fenced `TO_DISPATCH=(...)` block then consumed. That contract was LLM-runtime-emission fragile — a future SKILL.md edit could drop the emission instruction and the fence would execute with a literal placeholder. CI-side grep of the prose can prove the *instruction* still exists but cannot prove the model still *emits* the line. Option C eliminates this layer entirely. **New architecture:** the acquire call is inserted into the per-issue dispatch template BLOCK at ~`SKILL.md:2161-2186` (cherry-pick/direct) and at the per-issue PR-mode worktree-setup block at ~`SKILL.md:2219-2243`, immediately ABOVE the existing `create-worktree.sh` invocation. The orchestrator is already iterating issues to call `create-worktree.sh`; adding a sibling `claim-issue.sh acquire` call before it is a natural extension of the same prose iteration, requires no new model-emit contract, and reuses the existing prose-driven loop semantics. (Dispatch is prose-iterated — verified by `grep -n 'for[[:space:]]\+.*TO_DISPATCH' skills/fix-issues/SKILL.md` returning zero matches; the only `for N` loop in SKILL.md is at line 1100 for sync mode, NOT dashboard-mode dispatch.) **Backstop:** a PreToolUse hook on Bash invocations of `create-worktree.sh` denies the call when the resolved branch name matches `fix-issue-NNN` or `fix/issue-NNN` and no matching `.zskills/claims/issue-NNN/` exists. This means: if a future SKILL.md edit accidentally removes the acquire instruction from one of the two prose blocks, the hook fires at runtime and stops the orchestrator. The hook is the structural backstop the PICKS conformance grep could never be. **Scope discipline:** other `/do worktree`, `/do pr`, `/run-plan`, and `ensure-worktree.sh` invocations of `create-worktree.sh` use NON-fix-issue branch names (`pr-<plan-slug>`, `cp-<plan-slug>`, `wt-<slug>`, etc.) — verified by `grep -n 'BRANCH=' skills/create-worktree/scripts/create-worktree.sh` showing `${PREFIX}-${SLUG}` default. The hook MUST scope strictly to `^(fix-issue-|fix/issue-)[0-9]+$` so unrelated callers are untouched. (Round 4: replaces all of round 1-3's PICKS / W2.0 / W2.2 design.) **Latent `TO_DISPATCH`-array fragility stays as-is** — the original plan was incidentally fixing the "TO_DISPATCH never `=()`-assigned in any fence" issue by adding W2.0. Round 4 drops W2.0, leaving that latent fragility exactly where the user found it. Per the user's explicit stance, this is acceptable (a separate cleanup can materialise the array later; that cleanup is not blocked by this plan and this plan is not blocked by that cleanup).
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

A7. Single-pipeline `dashboard` mode behaviour is byte-for-byte identical to today when only one `/fix-issues` is running. **Verification (two-layer, round 4 restructured):** (a) MECHANISM LAYER — Phase 4 `tests/test-fix-issues-claim-regression-single.sh` drives `claim-issue.sh acquire` directly for three issues sequentially (no concurrent acquirer), asserts all three exit 0 and all three claim dirs exist; runs `sweep_stale_claims` on a no-stale-claims directory and asserts it is a no-op; runs `hooks/block-fix-issue-unclaimed.sh` against a `fix-issue-1` payload WITH the claim present and asserts exit 0 (no spurious deny). (b) INTEGRATION LAYER — PR-time manual repro: run `/fix-issues 3 dashboard auto` once against a stub fixture; record the selection order; attach to PR body as evidence selection matches the pre-claim baseline. Earlier draft attempted a golden-file automated regression but `/fix-issues` is not bash-test-invocable.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Claim primitive script + config + unit tests | ✅ Done | `6c9c6db` | 14 new tests; 4558/4558 pass |
| 2 — fix-issues inline acquire (cherry-pick/direct/PR) + PreToolUse backstop hook + per-mode release wiring | ✅ Done | `7d24a65` | new hook 229 LOC; +38 tests; 5263/5263 pass |
| 3 — Dashboard collector + renderer chip (drag-disabled) + fingerprint fix | ✅ Done | `4baae7e` | +61 tests; 5324/5324 pass; D7 confirmed (server.py untouched) |
| 4 — E2E concurrency test + baseline race test + /cleanup-merged sweep + conformance | ✅ Done | `9cf3594` | +24 tests (race-e2e 1, baseline 2, conformance 18, regression 3); 5348/5348 pass |

---

## Phase 1 — Claim primitive script + config + unit tests

### Goal

Create a single shared helper script `claim-issue.sh` exposing all claim operations as subcommands. Add the `execution.claim_ttl_seconds` config field. Add unit tests for the primitive in isolation, including the EEXIST-vs-ENOSPC distinction.

### Work Items

- [ ] **W1.1** — Create `skills/fix-issues/scripts/claim-issue.sh`. **Root resolution (DA4.1 — round 4b):** every subcommand resolves `MAIN_ROOT` at function entry via `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` and operates on `${MAIN_ROOT}/.zskills/claims/...` regardless of caller CWD. The script MUST NOT use `$PWD/.zskills/claims/` — the hook (W2.2c) and dashboard collector (W3.1) read from MAIN_ROOT, and the orchestrator typically `cd`s into a sprint worktree before per-issue dispatch (SKILL.md:961), so `$PWD` points at the wrong root at acquire time. Standard idiom — same pattern used at SKILL.md:2163, 2225, `write-landed.sh`, `worktree-add-safe.sh`, `sanitize-pipeline-id.sh`. Callers do NOT need to `cd` to MAIN_ROOT first — the script handles its own root resolution. Subcommands:
  - `acquire <N> --pipeline-id <id> --sprint-id <id>` — `mkdir ${MAIN_ROOT}/.zskills/claims/issue-<N>` and on success write `claim.json` ATOMICALLY: write to `${MAIN_ROOT}/.zskills/claims/issue-<N>/claim.json.tmp` then `os.replace` (Python) to `claim.json`. The `claim.json` body: `{schema_version, pipeline_id, sprint_id, issue, started_at}` — NO `worktree_path` (DA8), NO `host_pid` (DA2.1/DA2.2 — the script's self-captured PID is meaningless under Claude Code's process model; see D1/D4). If the atomic-write step fails after mkdir succeeded, the script `rmdir`s the claim dir before returning non-zero (no stub leak). Exit codes: 0 = acquired, 10 = EEXIST race lost (claim already held), 11 = other mkdir failure (EACCES/ENOSPC/EDQUOT/EROFS — abort with stderr diagnostic). Exit 10 vs 11 distinguished by inspecting `mkdir` stderr — DO NOT swallow with `2>/dev/null`. Map `File exists` → 10; everything else → 11. **Inside `claim.json` write/parse use Python `json` stdlib (no jq, per CLAUDE.md).**
  - `release <N> [--require-pipeline <id>]` — refuse if claim's `pipeline_id` doesn't match (prevents accidental cross-pipeline release). On match, **per-file removal: `rm -f ".zskills/claims/issue-${N}/claim.json"` then `rmdir ".zskills/claims/issue-${N}"`**. Per-file form is mandatory (not a fallback): `block-unsafe-project.sh.template:488` blocks all `rm -r ... .zskills/...` typed inline by an agent; only `rm -rf "$dir"` INSIDE this script body is hook-invisible (the hook sees the agent's Bash tool command, not the script body) — but the per-file shape is simpler, safer, and equally atomic in practice (claim.json removal then empty-rmdir). (R2/DA3.) Exit 0 on release, 0 on already-absent (idempotent), 12 on pipeline-mismatch.
  - `is-stale <N>` — read `claim.json`, parse `started_at`, compare to `NOW - TTL`. **Crash-window:** if the dir exists but `claim.json` is missing AND dir mtime is older than 30 seconds, treat as stale (catches mkdir-succeeded-then-writer-crashed). (R7.) Exit 0 = stale, 1 = fresh, 2 = no claim. TTL resolved from `execution.claim_ttl_seconds` (default 7200). Use Python for ISO-8601 parse (no `date -d` portability surprises). **No `kill -0` liveness check** — see D4 / DA2.1 / DA2.2.
  - `sweep` — iterate `.zskills/claims/issue-*`, call `is-stale` on each, release stale ones (using the script's own internal release path; do NOT shell out per-iteration). Prints one stderr line per swept claim (`fix-issues claims: swept stale claim issue-<N> pipeline=<id> age=<seconds>s reason=<ttl|metadata>`). Idempotent.
  - **`release-suffix` — DELETED (round 4).** Round 1-3 spec'd this bulk-release helper to clean up the not-yet-dispatched suffix of `TO_DISPATCH` on a sprint-abort path. Option C eliminates the dispatch-list-loop entirely: acquire is inline at each per-issue dispatch site, so at the moment of a worktree-add failure there is at most ONE in-flight claim to release (the failing issue's own). The bulk-release shape is unused; the subcommand is dropped from the script API. (Round 4.)
  - `list` — pure read; emit one TSV line per live claim: `<N>\t<pipeline_id>\t<age_seconds>`. (No worktree column — see D1 / DA8.) Used by dashboard collector and human debugging.
- [ ] **W1.2** — Mirror the script under `.claude/skills/fix-issues/scripts/claim-issue.sh` via `bash scripts/mirror-skill.sh fix-issues`.
- [ ] **W1.2.5** — **(Round 4: SCOPED DOWN.)** Round 1-3 spec'd `claim-fence-helpers.sh` with two functions — `sweep_stale_claims()` and `acquire_for_dispatch_list()` — because the architecture needed an extracted loop helper used by both runtime and tests. Option C eliminates the dispatch-list-loop entirely (acquire is inline at the per-issue dispatch site, one call per issue, no `TO_DISPATCH` iteration), so `acquire_for_dispatch_list` is no longer needed. Round 4 retains ONE helper only: `sweep_stale_claims()` — a thin sourceable wrapper around `claim-issue.sh sweep` used by the Phase 1 preflight sweep fence (W2.1). The function exists for testability (Phase 4 sources it to verify the preflight sweep semantics in isolation) and to keep the SKILL.md fence single-line (just `sweep_stale_claims || true`). Mirror to `.claude/skills/fix-issues/scripts/`. The `acquire_for_dispatch_list` function is DELETED from the spec.
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
  - `list` output is parseable: tab-separated, one line per claim, fields in documented order (NO worktree column per DA8).
  - **Concurrency test (two-backgrounded-bash, lifted from `tests/e2e-parallel-pipelines.sh` shape):** two parallel acquires for the same `N`; assert exactly one exits 0, the other exits 10; assert the winning pipeline's metadata persists in `claim.json`.
  - **Non-EEXIST → exit 11 distinction (EACCES):** force `mkdir` failure via `chmod 0500` on parent (cannot create children) and assert exit 11, NOT 10. **Note**: this tests EACCES specifically; the script lumps EACCES/ENOSPC/EDQUOT/EROFS into one "not-EEXIST" class — the test name reflects "non-EEXIST", not "ENOSPC". Actually exhausting filesystem space for an ENOSPC test (tmpfs of 1MB + fill it) is heavy for a unit test; the script doesn't differentiate within the not-EEXIST class so EACCES is a faithful stand-in. (DA10.)
  - **Atomic-write crash window:** simulate mkdir-success-then-write-failure by `chmod 0500` on the issue subdir after mkdir; assert acquire returns non-zero AND the claim dir is `rmdir`'d (no stub leak). (R7.)
  - **MAIN_ROOT resolution (DA4.1 — round 4b):** create a fixture repo with a sprint worktree at `/tmp/fixture-sprint-wt/`. `cd /tmp/fixture-sprint-wt/` (NOT MAIN_ROOT). Run `bash claim-issue.sh acquire 42 --pipeline-id A --sprint-id S`. Assert (a) the claim dir lands under `${MAIN_ROOT}/.zskills/claims/issue-42/` (NOT `/tmp/fixture-sprint-wt/.zskills/claims/issue-42/`), (b) acquire returns 0. Then `cd /tmp` (a non-git directory) and run release — assert it still resolves MAIN_ROOT correctly via `git rev-parse --git-common-dir` falling back to the script's own location or an explicit error (NOT silently writing to `/tmp/.zskills/`). Decision: when `git rev-parse --git-common-dir` fails (cwd has no git repo above), the script exits non-zero with stderr `fix-issues claim-issue.sh: cannot resolve MAIN_ROOT (not in a git working tree); cd into a project worktree first`. This is the structural-defense reading — silent fallback to `$PWD` would re-introduce the bug DA4.1 documents.

### Design & Constraints

- **MAIN_ROOT resolution discipline (DA4.1 — round 4b):** the script resolves `MAIN_ROOT` internally at function entry via `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` and anchors ALL filesystem ops (`mkdir`, atomic write, `rm -f`, `rmdir`, `list` enumeration, `sweep` traversal) at `${MAIN_ROOT}/.zskills/claims/`. NEVER `$PWD/.zskills/claims/`. Rationale: the per-issue acquire fence (W2.2a/b) executes AFTER the orchestrator's `cd "$WT_PATH"` at SKILL.md:961, so `$PWD` is a sprint worktree at acquire time. The hook (W2.2c) reads `${CLAUDE_PROJECT_DIR:-$PWD}/.zskills/claims/issue-<N>/` (MAIN_ROOT in hook subprocess context per `block-stale-skill-version.sh:402` precedent), and the dashboard collector (W3.1) explicitly takes `main_root: pathlib.Path` for its claim lookup. If the script defaulted to `$PWD`, claims would land inside the sprint worktree and (a) the hook would FALSE-DENY every valid `create-worktree.sh` call, (b) the dashboard chip would never appear. Mirrors the pattern used at SKILL.md:2163, 2225, `write-landed.sh`, `worktree-add-safe.sh`, `sanitize-pipeline-id.sh`. When `git rev-parse --git-common-dir` fails (no git repo in cwd ancestry), the script exits non-zero with a descriptive stderr — NO silent fallback to `$PWD`. Hook side: W2.2c specifies the hook resolves MAIN_ROOT via the same `git rev-parse` idiom rather than blindly trusting `$CLAUDE_PROJECT_DIR` (which is reliable in hook subprocess context per Anthropic docs, but defense-in-depth aligns the two resolution paths).
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

## Phase 2 — fix-issues inline acquire (per-issue dispatch sites) + PreToolUse backstop hook + release wiring

### Goal

Wire `claim-issue.sh acquire` into the per-issue dispatch template blocks (cherry-pick/direct at SKILL.md:2161-2186; PR mode at SKILL.md:2219-2243) immediately ABOVE each `create-worktree.sh` invocation. Add a PreToolUse hook (`hooks/block-fix-issue-unclaimed.sh`) that backstops the prose — denies any Bash invocation of `create-worktree.sh` whose resolved branch matches `fix-issue-NNN` or `fix/issue-NNN` and lacks a matching `.zskills/claims/issue-NNN/` directory. Add Phase 1 preflight sweep. Wire all release sites enumerated in D3.

### Work Items

- [ ] **W2.0 — DELETED (round 4, option C).** Round 1-3 spec'd a `TO_DISPATCH=(...)` materialisation fence between SKILL.md:1923 and 2002 to feed an acquire loop. Option C eliminates the acquire loop entirely (acquire is inline at each per-issue dispatch site, not loop-driven over `TO_DISPATCH`), so the materialisation fence is no longer required. The latent `TO_DISPATCH`-array fragility stays as-is per D2 (the user's explicit stance). The `PICKS: <numbers>` structured-output contract is also DELETED — the orchestrator no longer needs to emit a fence-substitutable line. Documented here for round-history traceability; do not re-introduce.
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
- [ ] **W2.2a — Inline acquire at the cherry-pick/direct per-issue dispatch site (round 4 / round 4b LOCKED shape).** Edit `skills/fix-issues/SKILL.md:2161-2186`. The block currently sets `ISSUE_NUM`, derives `WORKTREE_PATH`, then either resumes-existing-worktree or calls `create-worktree.sh`. **Inject the acquire call IMMEDIATELY ABOVE the `if [ -d "$WORKTREE_PATH" ]; then` branch** (line ~2167) so the acquire happens BEFORE any path that creates or resumes a worktree. **Round 4b locks the control-flow shape (R4.3 / DA4.5) — no implementer discretion**:
  ```bash
  # Acquire a single-host atomic claim on this issue BEFORE the worktree is
  # materialised. The per-issue dispatch is PROSE-iterated (no enclosing
  # fenced for-loop — verified by grep). On race-lost (exit 10), this fence
  # exits 0 to terminate cleanly; the orchestrator narratively proceeds to
  # the next issue's per-issue fence block. On filesystem error (exit 11),
  # the fence exits 11 to abort the sprint. The PreToolUse backstop hook
  # (block-fix-issue-unclaimed.sh) denies the create-worktree.sh call below
  # if no matching claim exists, so omitting this acquire fails closed at
  # runtime. (D2; round 4 option C; round 4b R4.3/DA4.5 — no `continue`.)
  CLAIM_HELPER="$CLAUDE_PROJECT_DIR/.claude/skills/fix-issues/scripts/claim-issue.sh"
  bash "$CLAIM_HELPER" acquire "$ISSUE_NUM" \
       --pipeline-id "$PIPELINE_ID" --sprint-id "$SPRINT_ID"
  ACQ_RC=$?
  if [ "$ACQ_RC" = 10 ]; then
    echo "fix-issues: claim race lost for issue $ISSUE_NUM (concurrent pipeline holds it); skipping — orchestrator proceeds to next issue." >&2
    exit 0   # terminate this per-issue fence; orchestrator narratively continues to next issue
  fi
  if [ "$ACQ_RC" != 0 ]; then
    echo "fix-issues: claim acquire failed for issue $ISSUE_NUM (rc=$ACQ_RC); aborting sprint." >&2
    exit "$ACQ_RC"
  fi
  ```
  **Locked semantics (round 4b — NO IMPLEMENTER DISCRETION):**
  - The per-issue fence MUST use `exit 0` on race-lost (NOT `continue`). The dispatch is prose-iterated — there is no enclosing fenced `for` loop (verified: `grep -n 'for[[:space:]]\+.*TO_DISPATCH' skills/fix-issues/SKILL.md` returns zero hits; the only `for` around line 2161 is the `for N in "${OPEN_NUMS[@]}"` at SKILL.md:1100 which is sync mode, not dashboard-mode per-issue dispatch).
  - Bare `continue` outside a `for`/`while` is a bash syntax warning that exits-status-1 the fence — would mis-interpret as a filesystem-error abort. EXPLICITLY FORBIDDEN.
  - The orchestrator's iteration semantics: this fence runs once per issue in the prose loop. Exit 0 on race-lost terminates THIS fence cleanly; the orchestrator's narrative iteration proceeds to the next issue's fence block. Exit 11 (or any non-zero non-10 rc) aborts the sprint.
  - W2.2b mirrors the same locked shape — single source of truth, both sites use `exit 0` for race-lost.
  - Implementer MUST NOT substitute `continue`, MUST NOT wrap the fence in a synthesized `for`, MUST NOT invent alternative control flow. The shape above is the spec.
  - **Conformance gate (W4.2 — round 4b extension):** grep `skills/fix-issues/SKILL.md` to assert the per-issue fences containing `claim-issue.sh acquire` ALSO contain `exit 0` (for the race-lost arm) AND DO NOT contain a bare `continue` token within 10 lines after the `acquire` call. Catches future drift to the `continue` shape.
- [ ] **W2.2b — Inline acquire at the PR-mode per-issue dispatch site (round 4 / round 4b LOCKED shape).** Edit `skills/fix-issues/SKILL.md:2219-2243`. The block sets `BRANCH_NAME="fix/issue-${ISSUE_NUM}"`, derives `WORKTREE_PATH`, then either resumes or calls `create-worktree.sh --branch-name "fix/issue-${ISSUE_NUM}" --allow-resume`. **Inject the SAME locked-shape acquire fence from W2.2a immediately above the `if [ -d "$WORKTREE_PATH" ]` branch** (line ~2228) — byte-for-byte identical (including `exit 0` on race-lost, NO `continue`). Only the surrounding block differs (PR-mode adds `--branch-name` to the `create-worktree.sh` call). Same locked prose-iteration discipline as W2.2a. Round 4b locks both sites to the same shape for conformance-greppability.
- [ ] **W2.2c — PreToolUse backstop hook (round 4, option C; round 4b hardening).** New file `hooks/block-fix-issue-unclaimed.sh`. Modeled after `hooks/block-main-edits.sh` (small, single-purpose, ~150 LOC; verified by `wc -l hooks/block-main-edits.sh` = 176). **Hook contract:**
  - Reads PreToolUse JSON envelope from stdin (`tool_name`, `tool_input.command`).
  - Filters: only Bash tool calls; only commands matching the regex `(create-worktree|ensure-worktree)\.sh\b` — round 4b widens this from `create-worktree\.sh\b` per R4.1/DA4.3. `ensure-worktree.sh` is the canonical wrapper at `skills/create-worktree/scripts/ensure-worktree.sh:218-223` that forwards `--prefix`/`--branch-name`/positional slug verbatim to the inner `create-worktree.sh` via subshell dispatch. The internal subshell spawn is NOT a Bash tool call from Claude Code's perspective, so the hook would never see the inner `create-worktree.sh` invocation — it only sees the agent's top-level wrapper call. Today /fix-issues per-issue dispatch uses raw `create-worktree.sh` (verified by `grep -n 'ensure-worktree\.sh' skills/fix-issues/SKILL.md modes/*.md` — only sprint-level hits at lines 291, 298, 933, 945 with `--prefix fix-issues` plural which doesn't match the hook's branch regex); the widening is preemptive against a future cleanup that DRYs up by routing per-issue materialisation through the wrapper. Widening is cheap because both scripts use identical argv conventions. (NOT a substring match — must be one of the two scripts' actual invocations, to avoid false-positives on prose mentions.)
  - **Argv tokenization discipline (DA4.2 — round 4b):** parse `tool_input.command` via Python `shlex.split` to recover a real argv list — DO NOT regex-extract over the command string. The fix-issues per-issue dispatch fences pass `--purpose "fix-issues; issue=${ISSUE_NUM}"` (SKILL.md:2172) and `--branch-name "fix/issue-${ISSUE_NUM}"` (SKILL.md:2233) — both contain the literal `fix-issue-NNN` / `fix/issue-NNN` token inside their values. A naive regex like `grep -oE 'fix-issue[- ][0-9]+'` would match those quoted values and yield the wrong issue number. Mitigation:
    ```python
    # Hook argv parser (Python — invoked from the bash hook via heredoc or temp file).
    import shlex, sys
    argv = shlex.split(cmd_str)
    # Walk argv linearly; track --prefix <next>, --branch-name <next>, collect positionals.
    prefix = None
    branch_name = None
    positionals = []
    i = 1  # skip argv[0] = "bash" or the script path
    # Skip leading bash + script-path tokens until we're past the create-worktree.sh / ensure-worktree.sh argument.
    while i < len(argv) and not argv[i].endswith(("create-worktree.sh", "ensure-worktree.sh")):
        i += 1
    i += 1  # advance past the script path itself
    while i < len(argv):
        tok = argv[i]
        if tok == "--prefix" and i + 1 < len(argv):
            prefix = argv[i + 1]; i += 2; continue
        if tok == "--branch-name" and i + 1 < len(argv):
            branch_name = argv[i + 1]; i += 2; continue
        if tok.startswith("--"):
            # Generic two-arg flag skip (--purpose <v>, --pipeline-id <v>, etc.) — assume all known flags take one value.
            if i + 1 < len(argv) and not argv[i + 1].startswith("--"):
                i += 2; continue
            i += 1; continue
        positionals.append(tok); i += 1
    slug = positionals[-1] if positionals else None
    # Compute branch via create-worktree.sh:222-228 precedence: BRANCH_NAME_OVERRIDE > PREFIX-SLUG > wt-SLUG.
    if branch_name:
        branch = branch_name
    elif prefix and slug:
        branch = f"{prefix}-{slug}"
    elif slug:
        branch = f"wt-{slug}"
    else:
        branch = None
    ```
    Only AFTER `branch` is computed via this argv-walk, test the regex `^(fix-issue-|fix/issue-)[0-9]+$`. Defensive rejection: if `prefix == "fix-issue"` but `slug` is non-numeric or non-positive, log a stderr warning and allow (don't deny — prevents accidental partial-match against malformed fences). The argv walker matches the actual precedence at `create-worktree.sh:222-228`; T4.2 includes a positive-control test with `--purpose "fix-issues; issue=99"` and positional `42` asserting the hook checks claim for issue 42 (positional), NOT 99 (purpose-value).
  - Gate: if the resolved branch matches `^fix-issue-[0-9]+$` OR `^fix/issue-[0-9]+$`, extract the issue number `NNN`. Resolve `MAIN_ROOT` via `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` (round 4b — mirrors the script's resolution per DA4.1), falling back to `${CLAUDE_PROJECT_DIR:-$PWD}` only if `git rev-parse` fails. Check `${MAIN_ROOT}/.zskills/claims/issue-${NNN}/` exists. If it does NOT exist, emit a PreToolUse `permissionDecision: deny` envelope (verbatim shape from `block-main-edits.sh:175`).
  - **Deny envelope text (DA4.4 — round 4b).** The `permissionDecisionReason` field carries verbatim recovery instructions, mirroring the `block-stale-skill-version.sh` precedent (CLAUDE.md "Skill versioning" — deny envelopes carry the exact `bash scripts/frontmatter-set.sh ...` recovery command). Locked text:
    ```
    STOP: create-worktree.sh for fix-issue-<NNN> denied — no claim found at $MAIN_ROOT/.zskills/claims/issue-<NNN>/.

    The per-issue dispatch fence at SKILL.md:2161-2186 (cherry-pick/direct) or SKILL.md:2219-2243 (PR mode) MUST call:

      bash $MAIN_ROOT/.claude/skills/fix-issues/scripts/claim-issue.sh acquire <NNN> --pipeline-id "$ZSKILLS_PIPELINE_ID" --sprint-id "$SPRINT_ID"

    immediately above the create-worktree.sh invocation. If this hook fired during a sprint, the SKILL.md prose has drifted — STOP, do not retry, file an issue.

    If acquire returns exit 10 (race lost — issue held by a concurrent pipeline), skip and proceed to the next issue. If exit 11 (filesystem error), abort the sprint.
    ```
    Substitute `<NNN>` with the parsed issue number and `$MAIN_ROOT` with the resolved value before emitting. The agent reading the deny output sees both the recovery command and the failure-protocol guidance ("STOP, do not retry, file an issue"); this is consistent with the round-3 "framework-broken claims need empirical falsification" memory anchor — the deny is a structural defense fire, not a transient failure.
  - Pass-through (allow): every other branch pattern (non-fix-issue prefixes like `pr-<slug>`, `cp-<slug>`, `wt-<slug>` used by `/do`, `/run-plan`, `ensure-worktree.sh`) returns exit 0 immediately. Confirmed callers using non-fix-issue branches: `skills/do/modes/pr.md` uses `--prefix do-pr`; `skills/run-plan/SKILL.md:1356` uses `--prefix cp`; `skills/create-worktree/scripts/ensure-worktree.sh` honors caller-passed `$PREFIX` which is never `fix-issue` outside `/fix-issues`. The hook is fail-open on all of them.
  - **Env-var resolution:** `CLAUDE_PROJECT_DIR` is set in hook subprocess context (verified in `block-stale-skill-version.sh:402` precedent: `SCRIPT="${CLAUDE_PROJECT_DIR:-$PWD}/scripts/skill-version-stage-check.sh"`). The hook prefers `git rev-parse`-derived MAIN_ROOT (round 4b — DA4.1 alignment) and falls back to `${CLAUDE_PROJECT_DIR:-$PWD}` when `git rev-parse` fails. **`ZSKILLS_PIPELINE_ID` is NOT used by this hook** — the claim is identified by issue number alone, not pipeline-id. Two concurrent pipelines BOTH attempting to acquire issue N will race at the `mkdir` primitive (D1); the hook only checks "some claim exists" — it does not enforce that the claim's pipeline_id matches the current orchestrator. This is correct because the acquire path (W2.2a/b) is what enforces ownership; the hook is a structural backstop to catch SKILL.md prose drift, not a per-pipeline auth gate.
  - **Subagent composition (R4.2 — round 4b).** Per Anthropic's documented additive hook behavior (https://code.claude.com/docs/en/sub-agents §"Hooks in subagent frontmatter"), subagent frontmatter `hooks:` declarations COMPOSE WITH (do not replace) project-level `.claude/settings.json` hooks. Once `block-fix-issue-unclaimed.sh` is registered in `settings.json`, it fires on EVERY Bash tool call from BOTH the orchestrator AND the implementer/verifier subagents — same composition pattern as `block-stale-skill-version.sh` (CLAUDE.md "Skill versioning" section explicitly documents this for the verifier). This is benign: the implementer/verifier subagents are dispatched AFTER the worktree is created (the orchestrator owns `create-worktree.sh` invocation; subagents `cd` into pre-existing worktrees and never call `create-worktree.sh` themselves — verified by `grep -rn 'create-worktree' .claude/agents/ skills/fix-issues/` showing only orchestrator-side hits). The hook is filter-scoped to `(create-worktree|ensure-worktree)\.sh\b`, so subagent Bash calls don't trip it. No carve-out needed.
  - **Race-window framing:** two concurrent `/fix-issues` orchestrator sessions are SEPARATE PROCESSES with independent timing. The atomic `mkdir` primitive (D1) wins exactly one acquire regardless of wall-clock spacing between the two `acquire` calls — milliseconds, seconds, or minutes apart. The hook does NOT introduce a new race window: by the time `create-worktree.sh` is being invoked, the orchestrator either holds the claim (acquire returned 0 in W2.2a/b) or it skipped this issue via `exit 0` (acquire returned 10). The hook is checking after-the-fact that a claim exists — the existence check is itself ordered after the acquire, so a successful acquire is always visible to the hook. (The acquire writes the claim dir atomically via mkdir, and `mkdir` is `O_EXCL` semantics on POSIX — no torn-read race.)
  - **Hook content-hash discipline (R4.5 — round 4b).** `hooks/block-fix-issue-unclaimed.sh` is a top-level hook at the repo's `hooks/` directory, NOT inside any skill subtree. It is therefore OUTSIDE every skill's content-hash boundary (`scripts/skill-content-hash.sh` recurses only the skill directory — verified by reading the script). No skill's `metadata.version` bumps from edits to the hook file itself. The hook IS indirectly reflected in `skills/update-zskills/SKILL.md` (via the install-bullet edit specified in the "Install wiring" item below), and that SKILL.md edit triggers the `update-zskills` `metadata.version` bump — but that's documenting the install path, not hashing the hook content. CI conformance: `tests/test-skill-conformance.sh` checks skill content-hash inputs only; the hook itself is covered by W4.2 conformance assertions (existence + mirror + settings.json registration) — verified that test-skill-conformance.sh does not directly hash top-level hooks.
  - **Install wiring:** copy as-is from `$PORTABLE/hooks/` to `.claude/hooks/`, register in `settings.json` as PreToolUse on the `Bash` matcher. Add a row to the canonical zskills-owned triples table at `skills/update-zskills/SKILL.md:1205-1213` immediately below the existing `block-bypassed-land-pr.sh` row. Add an install bullet to `skills/update-zskills/SKILL.md` Step C (after the `block-main-edits.sh` bullet at line 1096-1102). Mirror to `.claude/skills/update-zskills/SKILL.md`. Bump `update-zskills` `metadata.version`.
- [ ] **W2.5** — Release on Phase 3 1h agent timeout. Find the existing "Timed out = failed, period" path at ~SKILL.md:2072-2077. Where the orchestrator declares an agent failed and records "Timed out" in SPRINT_REPORT.md, also call `claim-issue.sh release $N --require-pipeline $PIPELINE_ID`.
- [ ] **W2.5.5** — Release on per-issue worktree-add failure (round 4 simplification). Phase 3 currently does `exit "$RC"` on `create-worktree.sh` failure at SKILL.md:2176-2179 (sprint-abort behaviour, preserved to avoid a cross-cutting behaviour shift). **Round 4 simplification:** because acquire is now inline (one claim acquired immediately before each `create-worktree.sh` call in the same per-issue prose iteration), there is at most ONE in-flight claim at the moment of any single worktree-add failure — the one we just acquired for THIS issue. Earlier-dispatched issues already have their own running fix agents (whose claims correctly remain held); later-iteration issues have not yet been acquired (the loop hasn't reached them). On the abort path: BEFORE `exit "$RC"`, release the failing issue's claim only. Implementation: wrap the per-issue `create-worktree.sh` invocation at SKILL.md:2170-2179 (cherry-pick/direct) AND SKILL.md:2231-2242 (PR mode) with a bash guard that, on non-zero RC, (a) calls `bash "$CLAIM_HELPER" release "$ISSUE_NUM" --require-pipeline "$PIPELINE_ID" || true`, (b) emits stderr diagnostic naming the failing issue, (c) executes the existing `exit "$RC"`. The `release-suffix` subcommand spec'd in W1.1 is therefore no longer used — round 4 removes it from Phase 1 (see updated W1.1).
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

- **Inline-acquire architecture (round 4, option C).** The acquire call is co-located with each `create-worktree.sh` invocation in the per-issue dispatch template blocks (cherry-pick/direct at SKILL.md:2161-2186; PR mode at SKILL.md:2219-2243). One acquire per issue, no loop over `TO_DISPATCH`, no fenced materialisation of the dispatch array. The orchestrator's existing prose-iterated dispatch loop (no fenced `for ... TO_DISPATCH` anywhere — verified) drives the iteration; the acquire is one new fence inside the existing per-issue template. Failure modes:
  - **Race lost (exit 10):** orchestrator `continue`s (or `exit 0`s — see W2.2a implementer note) to the next per-issue prose step. No worktree created for this issue this fire.
  - **Filesystem error (exit 11):** orchestrator aborts the sprint with non-zero exit. The failing issue has no claim to release (mkdir failed).
  - **Worktree-add failure AFTER successful acquire:** W2.5.5 releases the just-acquired claim before `exit "$RC"`.
- **PreToolUse backstop hook (W2.2c) is the structural defense.** Prose-driven acquire is fragile to future SKILL.md edits (an unrelated cleanup could accidentally remove the acquire fence). The hook fires on every Bash invocation of `create-worktree.sh` and denies the call when the resolved branch matches `fix-issue-NNN` or `fix/issue-NNN` and no matching claim exists. Scope is the branch pattern — strictly `^fix-issue-[0-9]+$` or `^fix/issue-[0-9]+$`. **All other branch patterns pass through (allow):** verified callers using non-fix-issue prefixes include `/do worktree`, `/do pr` (`--prefix do-pr`), `/run-plan` (`--prefix cp` at SKILL.md:1356), and `ensure-worktree.sh` (caller-passed prefix never `fix-issue` outside `/fix-issues`). The hook is fail-open on all of them.
- **Hook-vs-acquire race window framing.** Two concurrent `/fix-issues` orchestrator sessions in two terminals are SEPARATE PROCESSES with independent timing. The atomic `mkdir` primitive (D1) wins exactly one acquire regardless of wall-clock spacing between the two `acquire` calls — milliseconds, seconds, or minutes apart, the outcome is the same: one process gets exit 0 and the claim dir; the other gets exit 10. The hook does NOT introduce a new race window — by the time the hook fires (on the orchestrator's `create-worktree.sh` Bash call), the orchestrator has already executed the acquire fence and either holds the claim or skipped this issue. The hook's "claim dir exists?" check observes the result of the same atomic mkdir.
- **Hook env resolution.** The hook resolves `${CLAUDE_PROJECT_DIR:-$PWD}` (precedent: `block-stale-skill-version.sh:402`). It does NOT read `ZSKILLS_PIPELINE_ID` — claim ownership is enforced at acquire time by the `--require-pipeline` flag in release calls; the hook only checks "some claim exists for this issue," which is the structural property that prevents duplicate-dispatch racing.
- **W2.6 is split across THREE files** (`modes/pr.md`, `modes/cherry-pick.md`, `modes/direct.md`) — verified by `grep -n "case.*STATUS" modes/*.md` showing only `pr.md:175`; cherry-pick + direct don't dispatch `/land-pr` per-issue at all. (R3/DA1.) Cherry-pick + direct mode releases happen at per-issue success/failure terminal arms, not at a STATUS case.
- **W2.6a release table MUST be exhaustive over the 10 reachable `LAND_OUTCOME` values** (`merged`, `created`, `pr-ready`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed`). **`monitored` is excluded** — it is a STATUS value, not a LAND_OUTCOME value, and including it in the HOLD arm would be dead code (DA3.1). The unknown-LAND_OUTCOME fallback is HOLD — conservatively preserving claim integrity. (R2.3 corrected the keying from `$STATUS` to `$LAND_OUTCOME`; DA3.1 corrected the count from 11 to 10 by removing the unreachable `monitored`.)
- **W2.5.5 preserves sprint-abort semantics on create-worktree failure (round 4 simplification).** The existing `exit "$RC"` at SKILL.md:2176-2179 is a cross-cutting behaviour (used by all `/fix-issues` users, not just claim-mode). Changing it to `continue` would be a behaviour shift requiring its own design surface; instead, the plan releases the single in-flight claim (failing issue's own — option C eliminates the multi-claim suffix because acquire is inline, not loop-driven) on the abort path, then `exit "$RC"` as today. This means a single bad issue still aborts the whole sprint — consistent with current behaviour — but the failing-issue's held claim is cleaned up rather than leaking until TTL.
- **All bash fences referencing resolved config MUST source `zskills-resolve-config.sh` at the fence top.** The deny-list test at `tests/test-skill-conformance.sh` fence-local check fails closed.
- **No `2>/dev/null` on fallible ops.** The `|| true` on `claim-issue.sh sweep` (W2.1) is allowed because sweep is best-effort hygiene with no semantic impact on the sprint outcome; document this in a comment immediately above the line. Same justification for `|| true` on per-issue release calls when STATUS is already-failed (idempotent-on-absent semantics make release-after-release a no-op).
- **Tracking-marker discipline:** claims live under `.zskills/claims/`, NOT `.zskills/tracking/`. Do not add any `requires.*` / `fulfilled.*` / `step.*` markers from this phase.
- **The "Dashboard Ready is empty" branch at `SKILL.md:1410-1414` is unchanged.** Empty-Ready-from-state-file routes through `ship_sync_only_or_cleanup` as today. Under option C, the "all candidates claimed by concurrent pipelines" failure mode is per-issue (not a sprint-wide exit): each per-issue acquire that returns 10 skips to the next issue. If ALL issues in the dispatch iteration return 10, the prose loop naturally completes with zero worktrees created and the existing post-loop bookkeeping (sync-only commit + cleanup) runs as today. No new sprint-wide exit path is needed.
- **Phase 2 LOC estimate (round 4 revised):** ~60 LOC across SKILL.md + 3 mode files for the inline-acquire fences + release-call additions (W2.0 deletion removes ~25 LOC; W2.2a/b add ~35 LOC of inline-acquire blocks; W2.5.5 simplification trims ~10 LOC vs round 3); ~150 LOC for the new hook `block-fix-issue-unclaimed.sh` (modeled on `block-main-edits.sh` at 176 LOC); ~50 LOC `update-zskills` wiring (Step C bullet + canonical-triples row + mirror); ~450 LOC tests. Total Phase 2: ~710 LOC. Phase 1: claim-issue.sh ~280 (release-suffix removed) + claim-fence-helpers.sh ~30 (acquire_for_dispatch_list removed) + Phase 1 tests ~230 = ~540. Phase 3: ~130. Phase 4: ~620 (hook-scope tests added). Plan total ~2000 LOC — comparable to round 3's ~1900 LOC. The hook adds surface area; the loop-helper and PICKS contract subtract it. Net wash, but the failure-mode coverage is materially better.

### Tests

- [ ] **T2.1** — `tests/test-fix-issues-claim-acquire-inline.sh` (round 4 — restructured for option C). The test exercises the per-issue inline-acquire shape:
  - **Race-lost path (round 4b LOCKED shape):** pre-create `.zskills/claims/issue-42/` under MAIN_ROOT (simulating a concurrent pipeline's claim). Run the W2.2a-locked per-issue fence body verbatim with `ISSUE_NUM=42`. Assert the fence exits with **exit code 0** (per the locked `exit 0` race-lost arm — R4.3 / DA4.5). Assert the fence does NOT invoke `create-worktree.sh`. Mock `create-worktree.sh` via a `PATH` override that records every invocation; assert the recorded invocation count is 0. Additionally assert that `bash -n` parses the fence with NO `continue` token in the race-lost arm (gates the shape lock).
  - **Acquire-success path:** with no pre-existing claim, run the same fence body. Assert acquire returns 0, the claim dir is created, and the subsequent `create-worktree.sh` invocation IS recorded.
  - **Filesystem-error path:** force `mkdir` to fail with non-EEXIST (e.g. by `chmod 0500` on the parent — see W1.5's EACCES pattern). Assert the fence exits with the propagated rc=11 and does NOT silently continue.
  - **Hook backstop:** run `bash hooks/block-fix-issue-unclaimed.sh` against a fake PreToolUse stdin payload encoding `{"tool_name":"Bash","tool_input":{"command":"bash .claude/skills/create-worktree/scripts/create-worktree.sh --prefix fix-issue 42"}}` (no pre-existing claim). Assert hook exits non-zero with a `permissionDecision:"deny"` envelope on stdout. Then pre-create the claim and re-run; assert exit 0 (allow).
  - **Hook scope (negative control):** repeat the hook-backstop test with `--prefix cp` or `--prefix do-pr` (NOT `fix-issue`). Assert exit 0 (allow) without any claim-dir check — the hook MUST be a no-op on non-fix-issue branches.
  - **Hook ensure-worktree.sh coverage (round 4b — R4.1/DA4.3):** run the hook against a payload encoding `bash .claude/skills/create-worktree/scripts/ensure-worktree.sh --prefix fix-issue 42` (no pre-existing claim). Assert hook denies (the widened regex `(create-worktree|ensure-worktree)\.sh\b` must match the wrapper). Pre-create the claim and re-run; assert allow.
  - **Hook argv tokenization disambiguation (round 4b — DA4.2):** run the hook against `bash create-worktree.sh --prefix fix-issue --purpose "fix-issues; issue=99" --pipeline-id X 42`. The `--purpose` value literally contains `issue=99` but the positional slug is `42`. With a claim pre-existing at `.zskills/claims/issue-42/` (NOT `issue-99/`), assert allow. Without ANY claim, assert deny with `permissionDecisionReason` naming issue 42 (NOT 99). This locks the shlex-tokenized argv walk against future regression. Mirror test: same payload but with `--branch-name "fix/issue-77"` overriding the prefix-derived branch — assert the hook checks claim for issue 77 (the `--branch-name` override wins per create-worktree.sh:222-228 precedence).
  Replaces round-3's `tests/test-fix-issues-claim-acquire.sh` (which tested the deleted `acquire_for_dispatch_list` helper).
- [ ] **T2.2** — `tests/test-fix-issues-claim-release-pr.sh`: parameterised over the 10 reachable `LAND_OUTCOME` values from `modes/pr.md` — `merged`, `created`, `pr-ready`, `pr-ci-failing`, `rebase-conflict`, `rebase-failed`, `push-failed`, `create-failed`, `monitor-failed`, `merge-failed` (R2.3 — keying corrected from `$STATUS` to `$LAND_OUTCOME`; DA3.1 — `monitored` removed as unreachable). For each, set up a held claim, drive the W2.6a release/HOLD logic (via a small extracted shell function or by sourcing the fence body), assert release-or-HOLD per the D3 PR-mode row. **Negative assertion (DA3.1):** add a `monitored`-as-LAND_OUTCOME case parameterised in to assert it routes to the default/HOLD arm (because `monitored` is not in the explicit case list) — confirms an implementer who accidentally typed `monitored` into the case wouldn't silently match an unreachable value. Comment in the test: `# DA3.1 guard: monitored is a STATUS not LAND_OUTCOME; if it ever reaches here it must fall to HOLD default.`
- [ ] **T2.2b** — `tests/test-fix-issues-claim-release-cherry-pick.sh`: simulate the step-5b `.landed status: full` path and the step-5c `.landed status: partial` path; assert claim released in both arms (R2.2).
- [ ] **T2.2c** — `tests/test-fix-issues-claim-release-direct.sh`: simulate the four IMPLEMENTED terminal arms (`status: full`, `status: conflict` rebase-conflict, `status: conflict` FF-refused, `status: direct-push-failed`); assert claim released in each (DA2.6/DA3.3). **`direct-verify-failed` is NOT tested here** because the terminal is currently a code-comment placeholder at modes/direct.md:80 with no real dispatch/write. When that terminal lands as real code, the implementer of that future PR must extend this test with the fifth case as part of the same diff (tracked via the `<!-- aspirational -->` marker W2.6c places at the line-80 site).
- [ ] **T2.3** — Unit test for the unknown-LAND_OUTCOME fallback (PR mode only): pass `LAND_OUTCOME=garbage`, assert HOLD + stderr warning.
- [ ] **T2.4** — Unit test for worktree-add failure release (W2.5.5 — round 4 simplified): simulate `create-worktree.sh` returning non-zero immediately after a successful acquire; assert (a) that issue's claim is released, (b) the script exits with the create-worktree RC (sprint-abort preserved), (c) any earlier-dispatched issues' claims remain held (those agents are still running). The "not-yet-dispatched suffix release" assertion from round 3 is REMOVED — option C's inline acquire means there is no acquired-but-not-yet-dispatched suffix to release.

### Acceptance Criteria

- [ ] All T2.* tests green.
- [ ] `skills/fix-issues/SKILL.md` `metadata.version` bumped and mirror diff empty.
- [ ] `skills/update-zskills/SKILL.md` `metadata.version` bumped (new hook install bullet + canonical-triples row in W2.2c) and mirror diff empty.
- [ ] `hooks/block-fix-issue-unclaimed.sh` exists, executable, mirrored to `.claude/hooks/block-fix-issue-unclaimed.sh` (round 4 / W2.2c).
- [ ] `settings.json` registers the new hook on PreToolUse / Bash matcher per the canonical-triples table addition in W2.2c.
- [ ] `bash tests/test-skill-conformance.sh` green (forbidden-literals + fence-local config sourcing checks).
- [ ] `git diff --stat` for this phase touches only `skills/fix-issues/SKILL.md`, `skills/fix-issues/modes/pr.md`, `skills/fix-issues/modes/cherry-pick.md`, `skills/fix-issues/modes/direct.md`, `hooks/block-fix-issue-unclaimed.sh`, `skills/update-zskills/SKILL.md` (install bullet + triples row), the corresponding `.claude/` mirrors, `settings.json`, and `tests/test-fix-issues-claim-*.sh`. No collateral edits.

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

- [ ] **W4.1** — `tests/test-fix-issues-claim-race-e2e.sh`. (Round 4 — restructured for option C.) Lift the scaffolding from `tests/e2e-parallel-pipelines.sh`. Setup: fixture `.zskills/claims/` directory. Two backgrounded subshells each call `bash claim-issue.sh acquire 42 --pipeline-id <A|B> --sprint-id <A|B>` directly (not via a removed `acquire_for_dispatch_list` helper). Wait for both via `wait`. Capture each subshell's stdout/stderr to separate temp files. Assert: exactly ONE exits 0; the other exits 10; on-disk `.zskills/claims/issue-42/claim.json` contains the winner's `pipeline_id`. This proves the cross-process atomicity at the script level. **Concurrent-pipeline framing:** the two backgrounded subshells stand in for two `/fix-issues` orchestrator sessions in two terminals — they are separate processes with independent timing. The atomic `mkdir` primitive wins exactly one acquire regardless of wall-clock spacing between the two `acquire` calls. The test does not need to control the spacing precisely; any non-zero spacing produces the same result (one winner, one loser).
- [ ] **W4.1b** — **Negative-control / baseline race test** (CLAUDE.md "surface bugs don't patch"): `tests/test-fix-issues-claim-race-baseline.sh`. Same shape as W4.1, but invoke a STUBBED `claim-issue.sh` that always returns 0 without actually `mkdir`ing the claim dir. Assert BOTH calls "succeed" — proves the bug (duplicate-dispatch race) actually exists in the absence of the mechanism. Paired with W4.1, this gates: (a) the race is real without the mechanism, (b) the mechanism prevents it.
- [ ] **W4.2** — `tests/test-fix-issues-claim-conformance.sh`. Assertions (round 4 — extended for hook + inline acquire):
  - `claim-issue.sh` and `claim-fence-helpers.sh` exist under both `skills/fix-issues/scripts/` and `.claude/skills/fix-issues/scripts/` (mirror).
  - **`hooks/block-fix-issue-unclaimed.sh` exists** and is executable (round 4 / W2.2c).
  - **`.claude/hooks/block-fix-issue-unclaimed.sh` exists** (install mirror — verifies the `update-zskills` Step C bullet is in place).
  - **`settings.json` registers the new hook** on PreToolUse / Bash matcher (round 4 / W2.2c).
  - **Per-issue dispatch blocks contain the inline acquire call** — grep `skills/fix-issues/SKILL.md` for `claim-issue.sh acquire` and assert at least 2 hits (one for cherry-pick/direct at ~SKILL.md:2161-2186, one for PR mode at ~SKILL.md:2219-2243). Anchor regex: `claim-issue\.sh"?[[:space:]]+acquire`. This catches a future SKILL.md edit that accidentally removes the acquire fence — the hook is the runtime backstop, but this conformance grep gates the source-code invariant at CI time.
  - `claim-issue.sh acquire 0` rejects (non-positive integer guard).
  - `claim-issue.sh acquire abc` rejects (non-numeric guard).
  - **NO inline `rm -r|rf|--recursive` against `.zskills/claims/`** in `skills/fix-issues/SKILL.md`, `skills/fix-issues/modes/*.md`, or any test file outside `claim-issue.sh` itself — grep-asserts zero hits for the regex `\brm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*|--recursive)[[:space:]]+[^;&|]*\.zskills/claims`. (R2/R5/DA3.)
  - Run `hooks/block-unsafe-project.sh.template` against a fake Bash tool call payload `bash claim-issue.sh release 42 --require-pipeline X` and assert ALLOW (the script invocation is not a destructive command at the hook layer).
  - Run `hooks/block-unsafe-project.sh.template` against a fake Bash tool call payload `rm -rf .zskills/claims/issue-42` and assert BLOCK (negative control — protects the invariant that inline forms remain hook-blocked).
  - **Hook scope (positive):** run `hooks/block-fix-issue-unclaimed.sh` against `{"tool_name":"Bash","tool_input":{"command":"bash .../create-worktree.sh --prefix fix-issue 42"}}` with no claim — assert exit non-zero + deny envelope. Additionally assert the deny envelope's `permissionDecisionReason` contains the locked recovery-instruction text (round 4b — DA4.4): includes substring `STOP:`, includes `claim-issue.sh acquire 42`, includes `If acquire returns exit 10` race-skip guidance. Mirrors the `block-stale-skill-version.sh` deny-envelope shape.
  - **Hook scope (allow on existing claim):** same payload, with `.zskills/claims/issue-42/` pre-created under MAIN_ROOT — assert exit 0.
  - **Hook scope (ensure-worktree wrapper coverage — round 4b R4.1/DA4.3):** payload encoding `bash .claude/skills/create-worktree/scripts/ensure-worktree.sh --prefix fix-issue 42` with no claim — assert deny. Same payload with claim present — assert allow. Locks the widened regex.
  - **Hook scope (argv tokenization — round 4b DA4.2):** payload encoding `bash create-worktree.sh --prefix fix-issue --purpose "fix-issues; issue=99" --pipeline-id X 42` with claim pre-existing at `issue-42/` (NOT `issue-99/`) — assert allow. Same payload with NO claim at all — assert deny naming issue 42 in the deny envelope. Mirror: `--branch-name "fix/issue-77"` override — assert hook resolves branch to `fix/issue-77` (precedence per create-worktree.sh:222-228) and checks claim for issue 77.
  - **Hook scope (negative — non-fix-issue prefix):** payload with `--prefix cp 99` — assert exit 0 (allow, no claim check).
  - **Hook scope (negative — non-Bash tool):** payload with `tool_name: "Edit"` — assert exit 0 (allow, tool-name filter).
  - **Hook scope (MAIN_ROOT resolution — round 4b DA4.1):** set up a fake CWD inside a sprint worktree (`$MAIN_ROOT/.git/worktrees/fixture-sprint`), with the real claim at `$MAIN_ROOT/.zskills/claims/issue-42/`. Run the hook with `CLAUDE_PROJECT_DIR` unset, cwd set to the sprint worktree, and a `create-worktree.sh --prefix fix-issue 42` payload. Assert allow (the hook resolves MAIN_ROOT via `git rev-parse --git-common-dir` and finds the claim at the correct root). Negative: with the claim at `$SPRINT_WT/.zskills/claims/issue-42/` (wrong root) and no claim at MAIN_ROOT, assert deny. Locks the hook's MAIN_ROOT alignment with the script.
  - **Per-issue fence shape (round 4b R4.3/DA4.5):** grep `skills/fix-issues/SKILL.md` for `claim-issue.sh acquire`; for each hit, assert the surrounding 10 lines contain `exit 0` (race-lost shape) AND do NOT contain a bare `continue` token. Catches future drift to the `continue` shape.
  - `.zskills/claims/` is gitignored (likely already covered by `.zskills/` blanket — confirm and document).
- [ ] **W4.3** — `tests/test-fix-issues-claim-regression-single.sh`. (Round 4 — restructured for option C; `/fix-issues` remains unrunnable from a bash test.) Mechanism-layer assertions:
  - Drive `claim-issue.sh acquire 1`, `acquire 2`, `acquire 3` in sequence (no concurrent acquirer); assert all three exit 0, three claim dirs exist.
  - Call `sweep_stale_claims` on a no-stale-claims directory; assert it is a no-op (no claims removed; exit 0).
  - Run `hooks/block-fix-issue-unclaimed.sh` against a `fix-issue-1` payload with claim present; assert exit 0 (no-spurious-deny in single-pipeline path).
  Together these gate A7 ("single-pipeline `dashboard` mode behaviour is byte-for-byte identical to today when only one `/fix-issues` is running") at the mechanism layer. **Full end-to-end `/fix-issues 3 dashboard auto` regression** is moved to PR test plan as a MANUAL repro step (orchestrator-driven, single-shot, screenshot attached to PR body — see Phase 4 Acceptance Criteria) — NOT a `tests/run-all.sh` suite member.
- [ ] **W4.4** — Verify the existing `tests/test-skill-conformance.sh` passes — no new forbidden literals, no fence-local config-sourcing miss. Run `bash tests/run-all.sh` end-to-end and capture the output per the canonical idiom (`TEST_OUT=/tmp/zskills-tests/$(basename "$(pwd)") ...`). **Important: `tests/run-all.sh` uses an explicit `run_suite` list (NOT a glob)** — verified by reading the script. Phase 4 MUST add all new test scripts to this list. (R10.) The required additions (round 4 — `test-fix-issues-claim-acquire.sh` replaced by `test-fix-issues-claim-acquire-inline.sh`): `test-fix-issues-claim-script.sh`, `test-fix-issues-claim-acquire-inline.sh`, `test-fix-issues-claim-release-pr.sh`, `test-fix-issues-claim-release-cherry-pick.sh`, `test-fix-issues-claim-release-direct.sh`, `test-fix-issues-claim-collector.py` (wrap in a `.sh` shim that invokes pytest/unittest), `test-fix-issues-claim-render-dom.sh`, `test-fix-issues-claim-race-e2e.sh`, `test-fix-issues-claim-race-baseline.sh`, `test-fix-issues-claim-conformance.sh`, `test-fix-issues-claim-regression-single.sh`.
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

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review (reviewer + devil's-advocate + refiner), followed by round 4 (architectural pivot to inline-acquire + hook, option C) and round 4b (post-restructure validation closing 1 Blocker + 1 Major + 6 Minor findings against the option-C design).

**Convergence:** Round 4 made a single architectural pivot (drop PICKS / W2.0 / `acquire_for_dispatch_list`; introduce inline acquire at the per-issue dispatch sites + a PreToolUse backstop hook). Round 4b verified the restructure against empirical pressure and closed all 8 findings (DA4.1 MAIN_ROOT script-root pin; DA4.2 shlex-based argv tokenization in the hook; R4.1/DA4.3 ensure-worktree wrapper regex widen; R4.2 subagent-composition documentation; R4.3/DA4.5 `exit 0` race-lost shape lock; DA4.4 deny-envelope recovery-text lock; R4.4 Round History row format; R4.5 hook content-hash discipline note). All round 1-3 design decisions on D1 (claim storage), D3 (release table), D4 (TTL + crash-window), D5 (sweep sites), D6 (chip + drag-disable), and D7 (state schema unchanged) remain locked. The pivot was scoped strictly to D2 (acquire site) and its downstream test surface; release wiring (W2.6a/b/c), the dashboard (Phase 3), and `/cleanup-merged` sweep (W4.5) are unchanged. Plan is FINAL.

**Remaining concerns:** None of blocker or major grade. Two areas the implementer should watch:

- **`direct-verify-failed` is aspirational (DA3.3).** W2.6c documents the future integration site at modes/direct.md:80 via an inline `<!-- aspirational -->` HTML comment so a future implementer wiring the real terminal can find it. T2.2c does NOT test this case; when the terminal is implemented, that PR must extend T2.2c.
- **Latent `TO_DISPATCH`-array fragility (round 4 explicit stance).** `TO_DISPATCH` is referenced at SKILL.md:886, 1992, 2009, 2036, 2051, 2052, 2060-2062 but never `=()`-assigned in any fence; the trim at line 2052 references-then-reassigns it. The original plan was incidentally fixing this via W2.0; round 4 dropped W2.0, leaving the fragility in place. Per user direction this is acceptable — a separate cleanup can materialise the array later; that cleanup is not blocked by this plan and this plan is not blocked by that cleanup. Implementers should NOT touch the trim block.

### Round History

| Round | Reviewer findings | DA findings | Verified-and-fixed | Justified-not-fixed | New gaps |
|-------|-------------------|-------------|---------------------|----------------------|----------|
| 1     | 12 (R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12) | 15 (DA1-DA15) | 25 | 2 (DA12, R12 — both minor) | 0 |
| 2     | 7 (R2.1-R2.7)     | 7 (DA2.1-DA2.7) | 14 | 0 | 0 |
| 3     | 2 (R3 reviewer F1+F2) | 4 (DA3.1-DA3.4) | 5 (after dedup of F1↔DA3.1) | 0 | 0 |
| 4     | 0 (architectural pivot, not adversarial scoring) | 0 (architectural pivot) | 3 (D2 rewrite + W2.2a/b/c creation + W2.0/W1.2.5-acquire-helper deletion) | 1 (latent TO_DISPATCH fragility — user-acknowledged) | 0 |
| 4b    | 5 (R4.1-R4.5) | 5 (DA4.1-DA4.5 incl. 1 Blocker, 1 Major, 3 Minor) | 8 (DA4.1 MAIN_ROOT pin in W1.1+D&C+W2.2c+W4.2; DA4.2 shlex argv discipline in W2.2c+T2.1+W4.2; R4.1/DA4.3 ensure-worktree regex widen in W2.2c+T2.1+W4.2; DA4.4 deny-envelope text lock in W2.2c+W4.2; R4.3/DA4.5 `exit 0` shape lock in W2.2a+W2.2b+T2.1+W4.2; R4.2 subagent-composition note in W2.2c; R4.5 hook content-hash discipline note in W2.2c; R4.4 Round History row format) | 0 | 0 |

**Convergence test:** round 4 evaluated A/B/C on their empirical merits (verified prose-iterated dispatch, verified `create-worktree.sh` caller scope, verified hook-install convention, verified branch-name construction in create-worktree.sh:222-228). Option C was picked because (a) the failure mode is CI-gateable AND runtime-gateable (the hook fires at runtime if SKILL.md prose drifts; the conformance grep gates at CI; both layers are real backstops, unlike A's prose-grep-only defense), (b) the orchestrator is already iterating issues to call `create-worktree.sh`, so adding a sibling acquire call is a natural extension of existing prose iteration with no new model-emit contract, and (c) the load-bearing W2.0 materialisation fence (with its PICKS structured-output contract) is eliminated entirely, reducing plan surface area. Plan ready for `/run-plan`.

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

## Round 4 disposition summary

**Decision: Option C — drop PICKS, inline acquire at per-issue dispatch site, add PreToolUse backstop hook.**

**Why C beats A and B:**

- **Option A (status quo + conformance grep + halt guard):** the grep can only verify the *instruction* to emit `PICKS: <numbers>` still exists in SKILL.md prose; it cannot verify the LLM actually emits the line at runtime. Failure mode: a future SKILL.md edit accidentally drops the emission instruction → W2.0 fence executes with a literal placeholder → bash syntax error. The empty-placeholder halt-guard at most catches the error after the fact; the LLM-runtime-emission fragility is unfixable at the grep level.
- **Option B (registration script `register-picks <nums>`):** moves the LLM-emit problem from "emit a fence-substitutable line" to "invoke a script with picked numbers". Same fragility, different layer.
- **Option C (inline acquire + hook):** the orchestrator is ALREADY iterating issues to call `create-worktree.sh` per-issue (verified: prose-iterated dispatch; no fenced `for ... TO_DISPATCH` exists; only one fenced `for N in OPEN_NUMS` at SKILL.md:1100 for sync mode). Adding a sibling `claim-issue.sh acquire` call immediately above each `create-worktree.sh` invocation is a natural extension of the same prose iteration. The PreToolUse hook (`block-fix-issue-unclaimed.sh`) backstops the prose: if a future SKILL.md edit drops the acquire call, the hook fires at runtime on `create-worktree.sh` invocations for `fix-issue-NNN` / `fix/issue-NNN` branches and denies the call. Combined with a conformance grep (W4.2) that asserts `claim-issue.sh acquire` appears at least twice in SKILL.md, the failure mode is CI-gateable AND runtime-gateable. No load-bearing W2.0 fence, no LLM-emit contract.

**Empirical evidence verified (with file:line citations):**

1. **Dispatch is prose-iterated** — verified by `grep -n 'for[[:space:]]\+.*TO_DISPATCH' skills/fix-issues/SKILL.md` returning zero hits; only `for N in "${OPEN_NUMS[@]}"` at SKILL.md:1100 (sync mode, NOT dashboard-mode dispatch). Confirmed.
2. **`create-worktree.sh` callers** — verified by `grep -rn 'create-worktree.sh' skills/ block-diagram/`. Beyond `/fix-issues` (cherry-pick/direct at SKILL.md:2161-2186; PR mode at SKILL.md:2219-2243), callers include `/do pr` (`skills/do/modes/pr.md:65,84`, `--prefix do-pr`), `/run-plan` (`skills/run-plan/SKILL.md:1356`, `--prefix cp`), and `ensure-worktree.sh` (the thin wrapper at `skills/create-worktree/scripts/ensure-worktree.sh`).
3. **`ensure-worktree.sh` behaviour** — verified at lines 188-228: in-worktree no-op (line 196-200), main_protected gate (line 202-208), then dispatch to `create-worktree.sh` with the caller-passed `--prefix` (line 218-223). The wrapper always passes the prefix through; it does NOT inject `fix-issue` for callers other than `/fix-issues`.
4. **Branch-name construction** — verified at `create-worktree.sh:222-228`: `BRANCH="${PREFIX}-${SLUG}"` by default, or `BRANCH_NAME_OVERRIDE` if `--branch-name` is passed. For `/fix-issues`: cherry-pick/direct = `fix-issue-NNN` (prefix-derived); PR mode = `fix/issue-NNN` (override via `--branch-name`). Distinguishable from `do-pr-*`, `cp-*`, `wt-*`.
5. **Hook install convention** — verified at `skills/update-zskills/SKILL.md:1063-1102`: hooks live in `hooks/` (source), mirror to `.claude/hooks/` via Step C, register in `settings.json` per canonical-triples table at SKILL.md:1205-1213. Precedents: `block-main-edits.sh` (176 LOC), `block-stale-skill-version.sh` (450 LOC), `block-bad-cron.sh` (358 LOC).
6. **Hook env resolution** — verified at `block-stale-skill-version.sh:402`: `SCRIPT="${CLAUDE_PROJECT_DIR:-$PWD}/scripts/skill-version-stage-check.sh"`. The new hook follows the same precedent. It does NOT need `ZSKILLS_PIPELINE_ID` (the claim check is by issue number; ownership is enforced at acquire time via `--require-pipeline`).

**Race-window correction (from reviewer):**

The prior plan said "the race window between the trim and the acquire is microseconds because they run serial in one process". Round 4 corrects this framing. Two concurrent `/fix-issues` orchestrator sessions in two terminals are SEPARATE PROCESSES with independent timing. The relevant race spacing between their respective `acquire <N>` calls is governed by USER INVOCATION TIMING (when the user types or schedules each `/fix-issues`) and LLM RESPONSE LATENCY — NOT by in-process serial scheduling. The atomic `mkdir` primitive wins exactly one acquire regardless of wall-clock spacing — milliseconds, seconds, or minutes apart, the outcome is identical: one process gets exit 0 and the claim dir; the other gets exit 10. This is the correct framing wherever the plan references race semantics. The plan body has been updated accordingly (W2.2c and W4.1 design notes).

**Materially changed sections (round 4):**

- **D2 (acquire site)** — rewritten end-to-end. Drops the post-triage-pre-trim acquire-loop architecture. Acquire is now inline at per-issue dispatch sites in SKILL.md:2161-2186 (cherry-pick/direct) and SKILL.md:2219-2243 (PR mode). Documents the latent `TO_DISPATCH` fragility as user-acknowledged and explicitly out-of-scope.
- **W2.0 — DELETED.** Reason documented in-place.
- **W2.2 — DELETED.** Replaced by:
  - **W2.2a (NEW)** — Inline acquire at the cherry-pick/direct per-issue dispatch site (SKILL.md:2161-2186).
  - **W2.2b (NEW)** — Inline acquire at the PR-mode per-issue dispatch site (SKILL.md:2219-2243).
  - **W2.2c (NEW)** — PreToolUse backstop hook `hooks/block-fix-issue-unclaimed.sh`. Modeled on `block-main-edits.sh`. Denies `create-worktree.sh` calls for `fix-issue-NNN` / `fix/issue-NNN` branches without a matching claim. Allows all other branch patterns (`do-pr-*`, `cp-*`, `wt-*`, etc.) verbatim. Install wiring in `update-zskills` Step C + canonical-triples table row.
- **W1.2.5 — SCOPED DOWN.** `claim-fence-helpers.sh` retains only `sweep_stale_claims()`; `acquire_for_dispatch_list()` is deleted (option C eliminates the loop helper).
- **W1.1 — `release-suffix` subcommand DELETED.** Option C eliminates the not-yet-dispatched suffix to bulk-release.
- **W2.5.5 — simplified.** On worktree-add failure, release only the single in-flight claim (the failing issue's own).
- **T2.1 (renamed)** — `test-fix-issues-claim-acquire.sh` → `test-fix-issues-claim-acquire-inline.sh`. Tests the inline-acquire shape: race-lost path, acquire-success path, filesystem-error path, hook backstop (positive), hook scope (negative-controls on non-fix-issue prefixes and non-Bash tools).
- **T2.4** — drops the "not-yet-dispatched suffix release" assertion (no longer applicable).
- **W4.1** — restructured: two backgrounded subshells call `claim-issue.sh acquire` directly (not via the deleted `acquire_for_dispatch_list`). Concurrent-pipeline framing corrected to "separate processes, atomic mkdir wins regardless of wall-clock spacing".
- **W4.2 (conformance)** — adds hook-existence assertions, hook-scope assertions (positive on `fix-issue-` / `fix/issue-`, negative on `do-pr-` / `cp-` / non-Bash), and a positive grep for `claim-issue.sh acquire` appearing at least twice in SKILL.md (gates against future prose drift removing the inline acquire).
- **W4.3** — restructured for option C; tests the mechanism at the script + hook level.
- **W4.4** — test-list updated (`-acquire.sh` → `-acquire-inline.sh`).
- **Plan Quality + Round History** — round 4 row added; PICKS-fragility remaining-concerns entry replaced by the `TO_DISPATCH` latent-fragility and `continue`-semantics entries.

**Findings deferred to a follow-up review pass:** None. The pivot was scoped strictly to D2 and downstream tests. Release wiring (W2.6a/b/c), Phase 1 schema, Phase 3 dashboard, and `/cleanup-merged` integration are unchanged from round 3.

## Round 4b disposition summary

Round 4b validated the option-C restructure against empirical pressure — reviewer surfaced 5 minor findings; devil's-advocate surfaced 1 Blocker + 1 Major + 3 Minor + 1 Provocation. All 8 unique findings (after deduplicating R4.1↔DA4.3 and R4.3↔DA4.5) were verified against repo evidence and fixed at the work-item / test level. No findings deferred.

**Materially changed sections (round 4b):**

- **W1.1 root resolution (DA4.1 — CRITICAL BLOCKER)** — added an explicit "Root resolution" preamble: every `claim-issue.sh` subcommand resolves `MAIN_ROOT` at function entry via `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` and anchors ALL filesystem ops at `${MAIN_ROOT}/.zskills/claims/`. NEVER `$PWD/.zskills/claims/`. This is THE fix for the CWD/MAIN_ROOT mismatch DA flagged: the per-issue acquire fence runs after `cd "$WT_PATH"` (SKILL.md:961), so `$PWD` is a sprint worktree; the hook reads `${CLAUDE_PROJECT_DIR}` (= MAIN_ROOT) and the dashboard collector reads `main_root`. Without the script anchoring to MAIN_ROOT, every valid acquire would be hook-false-denied AND every chip would be invisible. Rationale fully documented in a new Design & Constraints "MAIN_ROOT resolution discipline" paragraph. W1.5 unit test added: `cd /tmp/fixture-sprint-wt/` (NOT MAIN_ROOT), call acquire, assert claim lands at MAIN_ROOT (not CWD).
- **W2.2c MAIN_ROOT alignment (DA4.1 hook side)** — hook resolves MAIN_ROOT via `git rev-parse --git-common-dir` for symmetry with the script; falls back to `${CLAUDE_PROJECT_DIR:-$PWD}` only on `git rev-parse` failure. Defense-in-depth alignment.
- **W2.2c argv tokenization discipline (DA4.2 — MAJOR)** — locked the hook's argv parser to Python `shlex.split` + linear argv walk that mirrors `create-worktree.sh:222-228`'s actual precedence (BRANCH_NAME_OVERRIDE > PREFIX-SLUG > wt-SLUG). Full Python code snippet inlined. Defense against the `--purpose "fix-issues; issue=NNN"` and `--branch-name "fix/issue-NNN"` flag values which contain the same `fix-issue-NNN` literal as the positional slug. T2.1 + W4.2 conformance tests added: positional `42` with `--purpose ... issue=99` → assert hook checks issue 42 (positional), NOT 99 (purpose-value). Defensive rejection: if `prefix == fix-issue` but slug is non-numeric/non-positive, log warning and allow (don't false-deny on malformed fences).
- **W2.2c ensure-worktree wrapper coverage (R4.1/DA4.3 — MINOR)** — widened hook regex from `create-worktree\.sh\b` to `(create-worktree|ensure-worktree)\.sh\b`. Verified `ensure-worktree.sh` is currently used for sprint-level worktrees only (SKILL.md:298, 945 with `--prefix fix-issues` plural — doesn't match the branch regex anyway), so the widening is preemptive against future cleanup that DRYs up per-issue dispatch via the wrapper. T2.1 + W4.2 add positive tests for the wrapper payload.
- **W2.2c subagent composition note (R4.2 — MINOR)** — added a Design & Constraints paragraph documenting that per Anthropic's additive-hook-composition behavior (https://code.claude.com/docs/en/sub-agents §"Hooks in subagent frontmatter"), the new hook fires on Bash calls from implementer/verifier subagents as well as the orchestrator. Benign: subagents `cd` into pre-existing worktrees and never call `create-worktree.sh` themselves (verified by grep). Same composition pattern as `block-stale-skill-version.sh` per the CLAUDE.md "Skill versioning" section.
- **W2.2c deny envelope text lock (DA4.4 — MINOR)** — locked the `permissionDecisionReason` JSON body to a verbatim recovery-instruction string mirroring `block-stale-skill-version.sh`'s precedent. Includes the exact `claim-issue.sh acquire` recovery command + the exit-10 race-skip guidance + a STOP directive ("do not retry, file an issue"). W4.2 conformance test added: deny-envelope payload must contain `STOP:`, `claim-issue.sh acquire <NNN>`, and `If acquire returns exit 10` substrings.
- **W2.2c hook content-hash discipline (R4.5 — MINOR)** — added a clarification paragraph: `hooks/block-fix-issue-unclaimed.sh` lives at the repo's `hooks/` top level and is OUTSIDE every skill's content-hash boundary (`skill-content-hash.sh` recurses only the skill directory). No skill `metadata.version` bump triggers from hook-file edits; the hook is indirectly reflected via the `update-zskills/SKILL.md` install-bullet edit. CI conformance gating happens at W4.2's existence + mirror + settings.json assertions, not via skill hash.
- **W2.2a + W2.2b `exit 0` shape LOCKED (R4.3/DA4.5 — MINOR / Provocation)** — replaced the implementer-discretionary `continue`-or-`exit 0` shape with a single LOCKED `exit 0` fence body. The fence body is now byte-for-byte specified in W2.2a, and W2.2b references the same shape. Removed the 200-word implementer note that punted on control flow. Bare `continue` is EXPLICITLY FORBIDDEN (bash syntax warning + status-1 exit outside a `for`/`while`). W4.2 conformance grep added: for each `claim-issue.sh acquire` hit in SKILL.md, surrounding 10 lines must contain `exit 0` AND must NOT contain a bare `continue` token.
- **T2.1 + W4.2 test additions** — new assertions for the 6 round-4b fixes: MAIN_ROOT resolution (DA4.1), shlex argv (DA4.2), ensure-worktree coverage (R4.1), deny envelope text (DA4.4), `exit 0` shape (R4.3), tokenization disambiguation under `--branch-name` override.
- **Round History row 4 format (R4.4 — MINOR, cosmetic)** — reformatted row 4 with integer counts (0/0/3/1/0) consistent with rows 1-3. Added row 4b with the full round-4b counts (5/5/8/0/0).
- **Plan Quality "Remaining concerns" cleanup** — removed the now-obsolete `continue`-semantics bullet (the shape is locked in W2.2a/b). Kept the two genuine remaining concerns (direct-verify-failed aspirational; TO_DISPATCH latent fragility user-acknowledged).

**Findings justified-not-fixed:** None. All 8 round-4b unique findings (after dedup) verified against repo evidence and fixed at work-item / test level.

**New gaps surfaced:** None. The restructure is now empirically validated end-to-end (script + hook + dashboard all resolve MAIN_ROOT identically; argv tokenization is shlex-disciplined; the `exit 0` shape is locked; deny envelopes carry actionable recovery text; the hook regex covers both create-worktree.sh and ensure-worktree.sh).

**Outcome:** Plan is FINAL. Ready for `/run-plan plans/fix-issues-claims.md pr`.
