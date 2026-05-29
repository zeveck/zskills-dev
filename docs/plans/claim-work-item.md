---
issue: 803
title: Ownership-aware work-item claims (self-re-entry in the two twin scripts)
created: 2026-05-29
status: active
---

# Plan: Ownership-aware work-item claims — self-re-entry in the twin claim scripts

> **Landing mode: PR** — `.claude/zskills-config.json` has `main_protected: true`,
> so the plan works in a named worktree on a feature branch and lands via
> `/land-pr`. No commit/cherry-pick to main.
>
> **Execution note (2026-05-29):** run via `/run-plan … finish auto`, which
> accumulates all phases on one branch (`feat/claim-work-item`) and opens a
> SINGLE PR for the whole plan — deliberately superseding the original
> per-phase-PR intent (the phases form one coherent #803 feature in a
> single-maintainer, agent-facing repo; one bundled PR is lower-overhead and
> all phases are verified+tested before merge). The per-phase "Lands its own
> PR" lines below are historical design notes, not the executed landing shape.

## Overview

Today only `/fix-issues` claims a GitHub issue before working it
(`skills/fix-issues/scripts/claim-issue.sh` → `.zskills/claims/issue-<N>/`), and
only `/run-plan` claims a plan (`skills/run-plan/scripts/claim-plan.sh` →
`.zskills/claims/plan-<slug>/`). `/do`, `/quickfix`, and `/investigate` claim
nothing — so a concurrent `/fix-issues` cron can grab the same issue one of them
is actively working, producing duplicate PRs / wasted compute. #803 asks for ONE
way for any skill to claim a work-item (issue **or** plan) before working it,
release on resolve, and the cross-cutting discipline propagated.

**The settled design ("B") does NOT build a `/claim-work-item` skill or a
dispatch wrapper.** The two claim scripts are already ~91% identical siblings
(`claim-plan.sh` header self-describes as "Sibling … mirrors the ~91% generic
structure"). The ONE genuinely-new behavior #803 needs is **ownership-aware
self-re-entry**: a pipeline re-acquiring its OWN claim must succeed (exit 0)
rather than collide. Today neither script reads the stored `pipeline_id` on
acquire, so the only existence check is the bare `mkdir … *"File exists"* →
return 10` — a pipeline re-acquiring its own claim gets exit 10, identical to a
foreign claim. That conflation is the bug behind `run-plan` SKILL.md:597.

The smallest correct change is therefore: **factor self-re-entry into a small
shared sourced helper and wire it into the EEXIST branch of BOTH twins.** No
rename, no new entry-point script, no schema change, no caller-interface change.
Because the script names and call shapes are untouched, the existing conformance
batteries stay green with little/no edit. Three downstream payoffs fall out:

1. `/fix-issues` and `/run-plan` keep calling the exact same scripts — they just
   gain self-re-entry for free.
2. `run-plan` SKILL.md:597's bespoke "rc=10 → decline" prose becomes correct by
   construction (claim-plan.sh now returns 0 on a genuine self-re-entry; rc=10
   then means *only* foreign, which is exactly what the decline arm should do).
3. The new consumers (`/do`, `/quickfix`, `/investigate`) can call
   `claim-issue.sh` **directly** with a synthesized `--sprint-id`, gaining
   acquire-on-pickup / release-on-resolve with no new machinery.

Then `run-plan` extends its existing acquire fence to also claim the plan's
`issue: N` (the #803 execution-window protection), and `CLAUDE_TEMPLATE.md`
carries the cross-cutting "claim before you work a tracked work-item" rule so it
auto-loads for every consumer (memory anchors don't propagate; CLAUDE_TEMPLATE
does).

### Verified current-state facts (cited against the worktree, post-#739/#742/#771/#776/#777)

- `claim-issue.sh` (368 lines): `acquire <N> --pipeline-id <id> --sprint-id <id>`
  at `:101-180`; the EEXIST branch is `mkdir_err=$(mkdir "$claim_dir" 2>&1)` →
  `case … *"File exists"*) return 10` at `:137-150`. `resolve_main_root()` via
  `git rev-parse --git-common-dir` parent, never `$PWD`, at `:62-74`. Schema
  `{schema_version, pipeline_id, sprint_id, issue, started_at}` written at
  `:155-169`. `is-stale` is the 30s crash-window check only (`:245-278`, no TTL).
  `validate_issue_number` REJECTS non-numeric input (`#`/quotes → `return 1`,
  usage-error) at `:80-95`.
- `claim-plan.sh` (439 lines): `acquire <slug> --pipeline-id <id>` at `:154-229`;
  identical EEXIST branch at `:186-199`. `resolve_main_root()` at `:103-114`.
  `_locate_sanitizer()` precedence (sibling create-worktree → `.claude/skills/`
  mirror → repo source) at `:75-94`. Schema adds `kind:"plan"`, `slug`,
  `current_phase`; `release` REQUIRES `--require-pipeline` (`:249-252`); `set-phase`
  mutator at `:290-347`; NO `is-stale`. **claim.json read patterns differ across
  the file:** `release` uses a `try/except → empty string` reader (claim-issue.sh:212-219;
  claim-plan.sh:265-272) that is SAFE on malformed/truncated JSON, but `set-phase`
  uses BARE `json.load()` with no try/except (claim-plan.sh:325-328) that RAISES
  on truncation. The new helper MUST copy the `release`-style reader, NOT set-phase's.
- **`run-plan` PIPELINE_ID is STABLE across chunked `finish auto` fires.**
  `TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]_' '[:lower:]-')`
  (SKILL.md:429); `PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"`
  (SKILL.md:443/493/569/588/868) — deterministic per plan. ⇒ a chunked re-fire
  re-acquires its OWN claim, hitting the rc=10 conflation today.
- **`/fix-issues` PIPELINE_ID is FRESH per sprint fire.**
  `SPRINT_ID="sprint-$(date -u +%Y%m%d-%H%M%S)-$ISSUE_TITLE_SLUG"`;
  `PIPELINE_ID="fix-issues.$SPRINT_ID"` (sprint.md:126-127) — timestamped ⇒
  self-re-entry never triggers for fix-issues; the new branch is inert+harmless
  for it.
- **`/do` and `/investigate` have NO `PIPELINE_ID` in their parent SKILL.md.**
  `grep -n PIPELINE_ID skills/do/SKILL.md` → 0 hits; `grep -n PIPELINE_ID
  skills/investigate/SKILL.md` → 0 hits. `/do`'s PIPELINE_ID is constructed
  ONLY inside the mode files — `worktree.md:30` and `pr.md:62`
  (`PIPELINE_ID="do.${TASK_SLUG}"`, AFTER `TASK_SLUG` is composed/sanitized);
  `direct.md` (25 lines) sets neither `TASK_SLUG` nor `PIPELINE_ID`. `/do`
  ALSO never parses an issue number into a variable (`grep -n "ISSUE=" 
  skills/do/SKILL.md` → 0 assignment; the only `ISSUE`/`TASK_SLUG` hits at
  SKILL.md:946/961 are prose). `/quickfix` DOES set `PIPELINE_ID="quickfix.$SLUG"`
  (SKILL.md, Tracking-setup block). ⇒ Phase 2 must SYNTHESIZE a PIPELINE_ID and
  PARSE the issue number for `/do` and `/investigate` (see W2.1/W2.2/W2.3 below);
  `/quickfix` reuses its existing PIPELINE_ID. THIS is the C1/M1 fix.
- **The twin scripts are NOT registered** in `script-ownership.md` (`grep -n claim
  …script-ownership.md` → 0 hits), nor in any STALE_LIST / tier1-shipped-hashes
  file (the only `claim-*` hits under `tests/` are test files). The new helper
  gets the SAME treatment: directly-authored skill script, NOT registered.
- `run-plan` acquire fence at SKILL.md:587-602 (rc=10 → "declined" `exit 0` at
  `:597`). Plan-claim release terminals: execute-phase.md:1199-1204 (already-
  complete no-op) and :1600-1608 (terminal merge, release call at :1600-1601),
  plus subcommands/stop-next-status.md (operator-stop release loop at `:124-165`,
  release call at `:154`). The operator-stop loop iterates `"$CLAIMS_ROOT"/plan-*`
  ONLY and gates on `pipeline_id` starting `run-plan.` — its inline comment at
  `:145-147` explicitly assumes fix-issues uses `issue-*/`, so it STRUCTURALLY
  never sweeps `issue-*/` dirs. THIS is the M2/M3 gap Phase 3 must close.
- `gh issue close <N>` is emitted in execute-phase.md `### 2. Close linked issue`
  at `:1352` (a model-substituted `<N>` placeholder, NOT a bash-extracted var);
  the terminal-merge plan-claim RELEASE is far away at `:1600-1601`. Ordering is
  correct (close precedes release) but the two sites are NOT adjacent — D9/W3.3
  must say "the release sites listed above," not "around `gh issue close`."

## Locked Decisions

### D1 — One shared sourced helper; wire into BOTH twins' EEXIST branch. NO wrapper, NO new skill.

**Decision.** Create one small POSIX-bash helper that, given a claim dir + the
caller's pipeline_id, decides self (0) vs foreign (10) when the claim already
exists. Both `claim-issue.sh` and `claim-plan.sh` SOURCE the locator but invoke
the helper as a `bash` SUBPROCESS from the EEXIST arm of `cmd_acquire` (the
exit-10/exit-0 contract requires a subprocess — sourcing-and-`exit` would kill
the caller). No `claim-work-item.sh`, no `/claim-work-item` skill, no
dispatch-by-kind layer.

**Rationale.** The scripts are already ~91% identical; the only new behavior is
self-recognition, which is a few lines. A wrapper or merged script would churn
both tested contracts (acquire flags differ: issue needs `--sprint-id`, plan
doesn't; release-flag requiredness differs; `set-phase` is plan-only) for zero
behavioral gain. "Surface bugs, don't patch" cuts the other way here: the fix
belongs IN the scripts' acquire path, factored to avoid divergence. `plans-claim-
chip-parity` D1 rejected `claim-resource.sh <kind> <key>` for exactly this
payload-divergence reason; that rejection still holds — we share only the
self-re-entry decision, not the whole script.

**Verification.** `grep -n claim skills/update-zskills/references/script-
ownership.md` → 0 hits (twins unregistered → helper unregistered, no table/total
churn). EEXIST arms confirmed at claim-issue.sh:137-150 and claim-plan.sh:186-199.

### D2 — Helper location: `skills/create-worktree/scripts/` (next to `sanitize-pipeline-id.sh`).

**Decision.** Co-locate the helper with `sanitize-pipeline-id.sh` under
`create-worktree`'s bundle. `claim-plan.sh` already crosses into that bundle via
`_locate_sanitizer()`, so the precedent and the lookup precedence already exist.
`claim-issue.sh` (no sanitizer dep today) gains a `_locate_*` sibling that mirrors
`claim-plan.sh:75-94` verbatim (sibling create-worktree → `.claude/skills/`
mirror → repo source-tree).

**Rationale.** Lane-portable (plugin vs `/update-zskills` mirror vs source tree)
exactly as the existing sanitizer locator already proves. Putting it in
`create-worktree` (a foundational, widely-sourced bundle) avoids creating a new
owner. Editing `create-worktree`'s bundle → bump `create-worktree`'s
`metadata.version` + re-mirror.

**Verification.** `claim-plan.sh:75-94` `_locate_sanitizer()` is the template;
`skills/create-worktree/scripts/sanitize-pipeline-id.sh` exists and is sourced
cross-skill today; the mirror dir `.claude/skills/create-worktree/scripts/`
exists for re-mirror.

### D3 — Self-re-entry semantics + the verbatim exit-code contract.

**Decision (helper logic).** Given `<claim_dir>` and `<caller_pipeline_id>`,
invoked only on the already-exists branch:
- If `claim.json` is ABSENT → return **foreign (10)**. (Never steal: an in-flight
  acquire window or a crashed-mkdir stub is not ours to claim. This is the
  conservative choice and matches the "never steal" rule below.)
- Else read the stored `pipeline_id` via Python stdlib json (NO jq) **using a
  `try/except → empty-string` reader captured into a shell variable** (mirror
  claim-issue.sh:212-219 / claim-plan.sh:265-272, NOT set-phase's bare
  `json.load()` at claim-plan.sh:325-328). A truncated/half-written/malformed
  `claim.json` MUST therefore yield an empty captured string → `"" != caller`
  → **foreign (10)**, deterministically, NEVER an exit-code-driven branch or a
  whole-acquire abort. Return **self (0)** iff the captured pipeline_id equals
  the caller's, **foreign (10)** otherwise.

**Decision (acquire wiring, both scripts).** In `cmd_acquire`, the EEXIST arm
(`case … *"File exists"*)`) calls the helper instead of unconditionally
`return 10`: self → `return 0`, foreign → `return 10`. The fresh-acquire path
(mkdir succeeded → write claim.json) is unchanged.

**Decision (exit-code contract — document verbatim in BOTH script headers):**

```
acquire <id> …
  0  — acquired-fresh OR self-re-entry (caller already owns this claim)
  2  — usage error
  10 — foreign-held by another pipeline (OR claim already exists but claim.json
       absent/malformed — never steal)
  11 — non-EEXIST mkdir failure / fs error / atomic-write failure
release <id> [--require-pipeline <id>]
  0  — released (or idempotently absent)
  2  — usage error
  12 — release pipeline-id mismatch (claim left intact)
```

**Rationale.** Self-re-entry is the single new behavior #803 names ("Self-re-entry
must be tolerated; cf. claim-plan.sh rc=10 on a pipeline re-entering against its
own claim"). Returning foreign when `claim.json` is absent OR malformed preserves
the atomic-mkdir adjudication of the fresh-start race and never races a
half-written claim.

**Verification.** Today acquire returns 10 on EEXIST regardless of owner
(claim-issue.sh:142-144, claim-plan.sh:190-192) — the stored pipeline_id is never
read at acquire time. The try/except reader at claim-issue.sh:212-219 /
claim-plan.sh:265-272 (release) is the SAFE template; the bare `json.load()` at
claim-plan.sh:325-328 (set-phase) is the one to AVOID. `release
--require-pipeline` and `set-phase` are the existing ownership-comparison
precedent the helper mirrors.

### D4 — MAIN_ROOT inside the helper resolves via `git rev-parse --git-common-dir` parent — NEVER `$PWD`.

**Decision.** The helper is handed an ABSOLUTE `<claim_dir>` by the caller (both
twins already compute `"${MAIN_ROOT}/.zskills/claims/<dir>"` after
`resolve_main_root`), so the helper does not re-resolve MAIN_ROOT — it operates
on the path it's given. The plan's re-acquire-from-a-worktree-cwd test (Phase 1)
proves the END-TO-END resolution still lands on the shared common-dir, not the
worktree `$PWD`, because the CALLER resolves it. If a future refactor has the
helper resolve MAIN_ROOT itself, it MUST copy the twins' resolver verbatim
(git-common-dir parent, hard-fail on git error, never `$PWD`).

**Rationale.** DA4.1: callers run from worktrees; a `$PWD` fallback would land
claims inside a worktree, false-deny create-worktree, and hide the dashboard
chip. Keeping resolution in the caller (where it already lives) is zero-
divergence by construction.

**Verification.** claim-issue.sh:62-74 and claim-plan.sh:103-114 both resolve via
git-common-dir parent and hard-fail (`return 1`) on git error — never `$PWD`.

### D5 — NO TTL / heartbeat / sweep / refresh. `is-stale` stays the 30s crash-window check only.

**Decision.** The helper adds zero aging logic. Lifecycle stays acquire-at-pickup
/ release-at-resolve-or-abandon, stale claims cleared only by explicit `release`.
`claim-issue.sh is-stale` keeps its current sole behavior (dir without claim.json
> 30s → stale).

**Rationale.** #684 (plan side) and #739 (issue side) deliberately removed the
TTL/heartbeat/sweep stack; mid-work expiry can kill a 50-100min impl agent's claim
and cause double-dispatch. A persistent stale claim is the accepted cheaper cost.

**Verification.** claim-issue.sh:245-278 is the crash-window check only; #739
header note confirms; claim-plan.sh has no `is-stale` at all.

### D6 — `/do`, `/quickfix`, `/investigate` call `claim-issue.sh` DIRECTLY with a synthesized `--sprint-id`. Each must FIRST establish a PIPELINE_ID and PARSE the issue number.

**Decision.** Each of the three calls `bash <claim-issue.sh> acquire "$N"
--pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"` (sprint-id synthesized
from their own pipeline_id — single rule, all three) on issue pickup, and
`release "$N" --require-pipeline "$PIPELINE_ID"` on resolve/abandon. No wrapper.
**But the acquire MUST be placed where a PIPELINE_ID and an issue-number variable
already exist** (see the per-consumer spec in Phase 2). Specifically:

- `/investigate`: synthesizes `PIPELINE_ID="investigate.issue-<N>"` (sanitized via
  the shared `sanitize-pipeline-id.sh`) at the point it parses `#N`, since it has
  none today.
- `/do`: the acquire moves INTO each mode file AFTER that file constructs
  `PIPELINE_ID="do.${TASK_SLUG}"` (worktree.md:30, pr.md:62), AND `/do` first
  parses the issue number into a variable (it has none today). `direct.md` does
  not construct a PIPELINE_ID/TASK_SLUG at all — Phase 2 either (a) synthesizes a
  minimal `PIPELINE_ID="do.<issue-or-slug>"` in direct.md before the acquire, or
  (b) skips the claim in direct mode if no issue number is in scope (the common
  case). The acquire is NOT placed in `do/SKILL.md` before mode dispatch —
  PIPELINE_ID is empty there and the call would fail usage-error exit 2.
- `/quickfix`: reuses its existing `PIPELINE_ID="quickfix.$SLUG"`.

Exit 10 (foreign) → STOP this one-shot invocation with a clear "issue #N is being
worked by another pipeline; declining" message (NOT "next candidate" — these are
one-shot, not sprint loops). Exit 11 → fs-error + stop. Exit 2 (usage) → an
internal bug (empty PIPELINE_ID / non-numeric N) → STOP + surface (it means the
acquire was wired before its inputs existed — the C1/M1 failure class).

**Rationale.** `claim-issue.sh` requires `--sprint-id`; these skills have no
sprint. Reusing pipeline_id as sprint-id keeps a single acquire shape and lets the
EXISTING conformance grep match without a rename. Dashboard's issue chip shows
`sprint_id == pipeline_id` (cosmetically odd but harmless — `_read_claims` and the
chip tolerate it). The PIPELINE_ID/issue-var prerequisite is the C1/M1 root cause:
the acquire shape is right, but the variables it consumes did not exist at the
originally-specced placement.

**Verification.** acquire requires both flags (claim-issue.sh:116-119) and a
NUMERIC issue (validate_issue_number:80-95 — so `$N` must be a bare integer);
release `--require-pipeline` optional but used here for ownership-safe release
(claim-issue.sh:210-224). `grep -n PIPELINE_ID skills/do/SKILL.md` → 0;
`skills/investigate/SKILL.md` → 0; `quickfix.$SLUG` present in
`skills/quickfix/SKILL.md`. mode-file PIPELINE_ID: worktree.md:30, pr.md:62;
direct.md (25 lines) sets neither.

### D7 — `/fix-issues` is NOT changed; `/run-plan` plan-claim wiring is NOT changed (only the script gains self-re-entry).

**Decision.** No `/fix-issues` migration: it already calls `claim-issue.sh`, so it
gains self-re-entry for free (inert because its pipeline_id is fresh per fire).
`/run-plan` keeps calling `claim-plan.sh acquire` exactly as today; Phase 1 only
changes the script's internals.

**Rationale.** Minimizes blast radius and keeps every existing conformance
battery green. The plan-claim conformance asserts only that `claim-plan.sh
acquire` precedes `### Execution` (test-plan-claim-conformance.sh:71-94) — caller
shape unchanged ⇒ green.

**Verification.** test-plan-claim-conformance.sh:71-94 checks acquire placement,
not the rc-arm semantics. fix-issues acquire-fence two-pass grep
(test-fix-issues-claim-conformance.sh Test 4 :112-123) greps the `$CLAIM_HELPER`
INDIRECTION (`CLAIM_HELPER="…claim-issue.sh"` + `bash "$CLAIM_HELPER" acquire`),
NOT a literal `claim-issue.sh acquire` — untouched by this plan.

### D8 — `run-plan` `:597` is correct by construction after Phase 1; optional prose cleanup only.

**Decision.** After Phase 1, claim-plan.sh returns 0 on a genuine self-re-entry,
so the rc=10 arm at run-plan SKILL.md:597 fires ONLY on truly-foreign claims —
which is exactly when "declined" is the right verdict. Phase 3 OPTIONALLY sheds
the now-redundant bespoke "same-pipeline re-acquire" hand-waving in the
surrounding prose (SKILL.md:580-602), but the rc=10 → decline arm STAYS (it is
now correct, not dead).

**Rationale.** The conflation that the `feedback_run_plan_claim_self_reentry`
anchor documented (rc=10 against the pipeline's OWN claim) disappears at the
source. No need to special-case holder-id in the fence.

**Verification.** SKILL.md:583-585 prose currently asserts "a second pipeline
already owns the plan" for ALL rc=10 — true only AFTER Phase 1 makes self-re-entry
return 0.

### D9 — Issue claim held for the plan's FULL lifetime; released ONLY at the plan's terminal release points. Issue-foreign at start is WARN-and-PROCEED, not abort.

**Decision.** When a plan's frontmatter carries `issue: N`, `/run-plan` acquires
`issue-<N>` at PLAN START (alongside the existing plan claim), using run-plan's
pipeline_id and `--sprint-id "$PIPELINE_ID"`. The issue number is **stripped to a
bare integer** (drop `#` and surrounding quotes) before being passed to
`claim-issue.sh` (which rejects non-numeric). The issue claim is acquired ONCE,
**NEVER released per-phase**, persists across idle gaps between chunked fires
(filesystem + no-TTL + self-re-entry make this automatic), and is released ONLY at
the SAME terminal sites where the plan claim is released (completion/merge
release at execute-phase.md:1600-1601, already-complete no-op at :1203,
operator-stop at subcommands/stop-next-status.md:154). Multi-issue plans →
multiple issue claims. Phases do NOT individually claim.

**Issue-foreign-at-start policy (the M2 design call — DECIDED):** when the issue
acquire returns **rc=10** (a `/fix-issues` cron or other pipeline already holds
`issue-<N>`), `/run-plan` MUST:
1. log a LOUD warning to stderr: `"issue #N is claimed by another pipeline;
   proceeding with plan execution, issue claim NOT held"`;
2. **PROCEED with the plan anyway — do NOT abort**, and crucially
3. **NOT release or leak the just-acquired PLAN claim** (the plan claim was won
   legitimately; it stays held).

Rationale: #739 removed auto-expiry, so a possibly-stale issue claim must not
block a deliberately-run plan. The plan owns the plan; the issue contention is a
softer signal surfaced to the operator, not a fatal collision. This is DELIBERATELY
DIFFERENT from the plan-claim rc=10 arm (which DOES `exit 0`-decline, because two
pipelines must never both drive the SAME plan). Do NOT mirror the plan-claim
decline arm for the issue acquire — that would let a stale issue claim abort a
legitimate plan AND, without an explicit plan-release-before-decline, leak the
plan claim (the C2-analogue on the run-plan side).

rc=11 on the issue acquire → Failure Protocol (genuine fs error). rc=2 (usage,
e.g. an un-stripped `#N`) → internal bug → STOP + surface.

**Rationale.** This is the #803 execution-window protection: a long plan should
hold its issue against a concurrent `/fix-issues` cron for its whole life, not
just one phase — but NOT at the cost of refusing to run a plan whose issue is
held by a stale claim. Self-re-entry (Phase 1) makes the re-acquire on each
chunked fire return 0, so a run-plan that DID win the issue never self-collides.

**Verification.** Plan-claim release terminals confirmed at
execute-phase.md:1199-1204 (no-op) + :1600-1608 (terminal merge, release at
:1600-1601) + subcommands/stop-next-status.md:124-165 (operator-stop, release at
:154). The plan rc=10 arm is `exit 0` at SKILL.md:597 — the issue arm is
INTENTIONALLY not that. `gh issue close` is at execute-phase.md:1352, NOT
adjacent to the :1600 release — D9/W3.3 reference the release SITES listed above,
not "around `gh issue close`."

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| Phase 1 — Shared self-re-entry helper + wire into both twins + tests | ✅ | `49e705a` | helper + both EEXIST arms wired; +15 test cases; 6485/6485 green |
| Phase 2 — Wire /do, /quickfix, /investigate onto claim-issue.sh | ⬚ | | |
| Phase 3 — run-plan issue-claim (execution-window protection) + operator-stop sweep + optional :597 cleanup | ⬚ | | |
| Phase 4 — CLAUDE_TEMPLATE recursive claim discipline + docs | ⬚ | | |

---

## Phase 1 — Shared self-re-entry helper + wire into both twins + tests

### Goal

Add ownership-aware self-re-entry to BOTH `claim-issue.sh` and `claim-plan.sh`
via a small shared sourced helper, so a pipeline re-acquiring its OWN claim gets
exit 0 (success) instead of exit 10 (foreign). No rename, no schema change, no
caller-interface change. At the end of this phase, `run-plan` SKILL.md:597 is
fixed for free, and `/fix-issues` is unaffected (its fresh-per-fire pipeline_id
never self-collides).

### Work Items

- [ ] **W1.1 — Create the helper.** New file
  `skills/create-worktree/scripts/claim-self-reentry.sh`. Contract: given args
  `<claim_dir> <caller_pipeline_id>`, exit 0 = self (proceed), exit 10 = foreign
  (decline). **Invocation mode: bash SUBPROCESS, never sourced for the decision**
  (the `exit 10`/`exit 0` contract would terminate a sourcing caller). Logic per
  D3: if `<claim_dir>/claim.json` ABSENT → exit 10; else read stored `pipeline_id`
  via the `_CLAIM_PYTHON` precedence
  (`${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}`, Python stdlib
  json, NO jq) **using a `try/except → print('')` reader captured into a shell
  variable** (mirror claim-issue.sh:212-219 / claim-plan.sh:265-272 — NOT the bare
  `json.load()` at claim-plan.sh:325-328). A truncated/malformed claim.json MUST
  yield empty → exit 10 (foreign, never steal), deterministically. Exit 0 iff the
  captured pipeline_id equals `<caller_pipeline_id>`, else exit 10. `set -u`;
  header documents the contract verbatim.
- [ ] **W1.2 — Add a `_locate_self_reentry()` to `claim-issue.sh`** mirroring
  `claim-plan.sh:75-94` `_locate_sanitizer()` precedence verbatim: sibling
  `create-worktree/scripts/claim-self-reentry.sh` → repo-source
  `../../../skills/create-worktree/scripts/…` → `${CLAUDE_PROJECT_DIR}/.claude/
  skills/create-worktree/scripts/…` → `${CLAUDE_PROJECT_DIR}/skills/…`. Add the
  same locator to `claim-plan.sh` (it can reuse the `_CLAIM_SCRIPT_DIR` anchor it
  already computes at :71). The locator is SOURCED at script load; the resolved
  helper PATH is then invoked as a bash subprocess from the EEXIST arm.
- [ ] **W1.3 — Wire `claim-issue.sh` EEXIST arm.** At `:141-150`, replace the
  unconditional `*"File exists"*) return 10` with: locate + invoke the helper as
  `bash "$helper" "$claim_dir" "$pipeline_id"` (both in scope at this branch — C1
  confirms); on helper exit 0 → `return 0`; on helper exit 10 → `return 10`; if
  the helper cannot be located → `return 10` (conservative: never silently steal;
  emit a one-line WARN to stderr). (Note: the existing EEXIST arm is SILENT on the
  10 path today; no conformance test asserts silence or counts python invocations,
  so adding the locate+invoke is safe.)
- [ ] **W1.4 — Wire `claim-plan.sh` EEXIST arm** identically at `:189-198`,
  passing `"$claim_dir"` and `"$pipeline_id"`.
- [ ] **W1.5 — Update BOTH script headers** with the verbatim exit-code contract
  from D3 (acquire 0 now covers self-re-entry; 10 now covers "foreign OR
  claim.json absent/malformed — never steal").
- [ ] **W1.6 — Tests for the helper + self-re-entry on both kinds.** New
  `tests/test-claim-self-reentry.sh`: (a) helper unit — claim.json absent → 10;
  matching pipeline_id → 0; mismatching → 10; **truncated/malformed claim.json
  → 10** (write `{"pipeline_id": "x"` with no closing brace; assert exit 10, NOT
  a python traceback / non-10 exit). (b) `claim-issue.sh` integration — acquire
  fresh → 0; re-acquire SAME pipeline_id → 0; DIFFERENT pipeline_id → 10;
  dir-without-claim.json → 10. (c) `claim-plan.sh` integration — same four cases
  with a slug. (d) **re-acquire-from-a-worktree-cwd case**: create a real worktree
  (or simulate via a nested checkout sharing the common dir), `cd` into it,
  re-acquire the same id — assert exit 0 AND that the claim dir is under the
  shared common-dir's `.zskills/claims/`, NOT the worktree's `$PWD`. This proves
  MAIN_ROOT still resolves to the shared common-dir.
- [ ] **W1.7 — Version bump + mirror.** Bump `create-worktree` `metadata.version`
  (date `America/New_York` + recomputed content hash via
  `scripts/skill-content-hash.sh`), AND `fix-issues` + `run-plan`
  `metadata.version` (their bundles changed). Re-mirror each via
  `scripts/mirror-skill.sh <name>`.
- [ ] **W1.8 — Confirm no script-ownership / STALE_LIST / hash-file edits.** The
  helper is directly-authored skill machinery, same as the twins; verify
  `grep -n claim skills/update-zskills/references/script-ownership.md` is still 0
  and that no tier1-shipped-hashes / STALE_LIST entry is needed.

### Design & Constraints

- **Helper logic (verbatim).** On already-exists: claim.json absent OR malformed
  → foreign (10, never steal); else self (0) iff stored `pipeline_id == caller`,
  foreign (10) otherwise. Python stdlib json with `try/except → print('')`
  captured into a shell var (mirror release readers, NOT set-phase's bare
  `json.load()`), NO jq, `ZSKILLS_PYTHON` precedence.
- **Helper invocation mode: bash SUBPROCESS** (not sourced for the decision) — the
  exit-code contract requires a subprocess; matches the twins' `bash "$sanitizer"`
  pattern (claim-plan.sh:136).
- **Exit-code contract (verbatim, both scripts):** acquire — 0 acquired-fresh OR
  self-re-entry; 2 usage; 10 foreign-held (or claim.json absent/malformed); 11 fs
  error. release — 0 released/idempotent; 2 usage; 12 release pipeline-id mismatch.
- **HARD CONSTRAINT: NO TTL / heartbeat / sweep / refresh** (preserve #684/#739).
  `is-stale` stays the 30s crash-window check only.
- **MAIN_ROOT never `$PWD`** — resolved by the CALLER via `git rev-parse
  --git-common-dir` parent (claim-issue.sh:62-74, claim-plan.sh:103-114); the
  helper operates on the absolute claim_dir it's handed. The worktree-cwd test
  (W1.6d) proves end-to-end resolution.

### Acceptance Criteria

- `tests/test-claim-self-reentry.sh` passes all cases (helper unit incl.
  truncated-JSON → 10 + both-kind integration + worktree-cwd).
- `claim-issue.sh acquire N --pipeline-id P --sprint-id S` twice with the SAME P
  exits 0 both times; with a DIFFERENT P the second exits 10.
- `claim-plan.sh acquire SLUG --pipeline-id P` twice with the SAME P exits 0 both
  times; DIFFERENT P → 10.
- A claim dir created with `mkdir` but no claim.json → acquire returns 10 (never
  steals); a truncated claim.json → 10 (never crashes the acquire).
- All EXISTING claim batteries (`tests/test-fix-issues-claim-*.sh`,
  `tests/test-plan-claim-*.sh`) still pass unchanged (their double-acquire tests
  use DISTINCT pids → still expect foreign 10).
- `bash tests/run-all.sh` is green; skill version bumps present; mirrors byte-equal.

### Dependencies

None. This phase is self-contained and lands its own PR.

---

## Phase 2 — Wire /do, /quickfix, /investigate onto claim-issue.sh

### Goal

Give the three issue-capable consumers acquire-on-pickup / release-on-resolve via
direct `claim-issue.sh` calls (synthesized `--sprint-id "$PIPELINE_ID"`), so a
concurrent `/fix-issues` cron can't double-work an issue one of them is on. No
wrapper; the new per-consumer conformance sentinels grep the EXISTING script name
with zero rename churn. **Every acquire is placed where a PIPELINE_ID and an
issue-number variable already exist** (the C1/M1 fix).

### Work Items

- [ ] **W2.1 — `/investigate` (synthesize PIPELINE_ID + parse `#N`).** `/investigate`
  has NO PIPELINE_ID today (`grep -n PIPELINE_ID skills/investigate/SKILL.md` → 0).
  At the `#N` parse (SKILL.md:54, Phase 1 step 1, "If `#N`, fetch the issue"),
  Phase 2 must: (1) extract the bare integer issue number into `$N` (strip `#`),
  (2) synthesize `PIPELINE_ID="investigate.issue-$N"` routed through
  `sanitize-pipeline-id.sh`, (3) acquire BEFORE reproduction work. Because
  `/investigate` is a prose-driven interactive skill (abandon points are model
  "STOP/Report" instructions, NOT bash `exit`s — two-attempt-limit at :186-191,
  reproduction-skip at :74-88, couldn't-find-root at :261, plus the one hard bash
  `exit` at :215 config-missing), W2.1 must (a) place a concrete `release` bash
  block on the SUCCESS path at the terminal Report (SKILL.md:233+), AND (b) add a
  prose instruction at EACH abandon STOP: "before stopping, run `bash
  <claim-issue.sh> release \"$N\" --require-pipeline \"$PIPELINE_ID\"`." There is
  no single bash terminal that runs on every path, so the release must be wired
  both as a success-path bash block and as an explicit per-STOP prose step. Skip
  acquire entirely when the arg is a bare description (no issue number).
  - acquire: `bash <claim-issue.sh> acquire "$N" --pipeline-id "$PIPELINE_ID"
    --sprint-id "$PIPELINE_ID"`; exit 10 → print "issue #N is being worked by
    another pipeline; declining" + stop; exit 11 → fs-error + stop; exit 2 →
    internal bug (empty PIPELINE_ID / non-numeric N) → stop + surface.
- [ ] **W2.2 — `/do` worktree + direct modes — move acquire INTO the mode files;
  add issue-number parsing.** `/do` SKILL.md has NO PIPELINE_ID and NO issue
  variable (`grep -n PIPELINE_ID skills/do/SKILL.md` → 0; no `ISSUE=` assignment).
  PIPELINE_ID is constructed only in `worktree.md:30` / `pr.md:62`
  (`do.${TASK_SLUG}`); `direct.md` (25 lines) sets neither. Therefore:
  - **(a) Parse the issue number in `/do`.** Add issue-number extraction (the
    number is only reachable via `--force` triage override of the `/fix-issues`
    redirect at SKILL.md:320). Store the bare integer in a variable propagated
    into the mode files; if no issue number is in scope, the consumer claims
    nothing (the common /do case).
  - **(b) worktree mode** (`skills/do/modes/worktree.md`): acquire AFTER
    `PIPELINE_ID="do.${TASK_SLUG}"` is set (worktree.md:30) and after worktree
    creation, BEFORE impl dispatch. Release in **`/do` Phase 5 Report**
    (SKILL.md:859 — the universal terminal reached on BOTH auto and non-auto
    exits) AND the error-handling exits — **NOT Phase 4 Land** (SKILL.md:817-819
    is `AUTO_FLAG=1`-gated; a Phase-4-only release leaks on the dominant non-auto
    path).
  - **(c) direct mode** (`skills/do/modes/direct.md`): direct.md constructs no
    PIPELINE_ID/TASK_SLUG. EITHER synthesize a minimal
    `PIPELINE_ID="do.<bare-issue>"` (sanitized) before the acquire, OR skip the
    claim in direct mode when no issue number is in scope. Spell out which in the
    implementation (the latter is acceptable — direct mode is rarely issue-driven).
  - Do NOT place the acquire in `do/SKILL.md` before mode dispatch (SKILL.md:715-725):
    PIPELINE_ID is empty there → `--pipeline-id ""` → usage-error exit 2.
- [ ] **W2.3 — `/do` PR mode** (`skills/do/modes/pr.md`) — acquire after
  PIPELINE_ID + worktree creation; release in the finalize block; INLINE-release
  before the post-acquire early exits. PIPELINE_ID is set at pr.md:62 and the
  worktree is created at A5 (~pr.md:82). Acquire AFTER A5 (so A1 slug guards at
  pr.md:21/25 and A5's `exit "$RC"` at pr.md:82 are PRE-acquire). Release in the
  explicit-finalize `case "$LAND_OUTCOME"` block at pr.md:433-438
  (`merged|created|pr-ready` → release; `*` → release-on-failed too — release
  regardless of created vs merged). **C2 FIX — the post-acquire-pre-finalize early
  exits MUST inline-release before exiting**, exactly as the existing no-result-file
  exit at pr.md:270-274 inline-cleans its tracking markers. The exit sites that
  are AFTER the (post-A5) acquire and BEFORE the :433 finalize are: A7 body-compose
  guards `exit 5`/`exit 2` (pr.md:153/157) and the no-result-file `exit 1`
  (pr.md:274). At each, add a `bash <claim-issue.sh> release "$N"
  --require-pipeline "$PIPELINE_ID"` immediately before the `exit` (guarded by
  "only if an issue claim was acquired"). Do NOT copy `/fix-issues`'s
  HOLD-on-`created` arm (fix-issues pr.md HOLDs because a later sprint fire re-runs
  /land-pr to release; /do is one-shot with no later fire — HOLD would leak forever).
- [ ] **W2.4 — `/quickfix`.** `/quickfix` already sets `PIPELINE_ID="quickfix.$SLUG"`
  (Tracking-setup block). Parse the issue number (bare integer) if one is in scope.
  Acquire around the Tracking-setup block (where `PIPELINE_ID` is established and
  the `started` marker is written), BEFORE branch creation. Release in the Phase 7
  post-`/land-pr` explicit-finalize (the caller-loop block keyed on
  `$LAND_OUTCOME`), release-on-resolution regardless of created vs merged, AND the
  fail-finalize abandon sites (test fail, commit fail, push fail — the inline
  cleanup sites quickfix already has). Skip acquire when no issue number is in
  scope (the common case — /quickfix usually works an in-flight edit, not an issue).
- [ ] **W2.5 — Per-consumer `metadata.version` bump + mirror** for
  `do`, `quickfix`, `investigate` via `scripts/mirror-skill.sh`.
- [ ] **W2.6 — Conformance sentinels** in `tests/test-skill-conformance.sh`: for
  EACH of `do` (incl. `do/modes/worktree.md`, `do/modes/pr.md`,
  `do/modes/direct.md` per where the acquire actually lands), `quickfix`,
  `investigate`, assert the relevant file contains a `claim-issue.sh … acquire`
  AND a `claim-issue.sh … release` (or `release …--require-pipeline`). **Match the
  ACTUAL wiring shape** — if a consumer uses a `$CLAIM_HELPER`-style indirection
  like fix-issues (test-fix-issues-claim-conformance.sh greps
  `CLAIM_HELPER="…claim-issue.sh"` + `bash "$CLAIM_HELPER" acquire`), the sentinel
  must grep that indirection; if it uses a literal `bash <path>/claim-issue.sh
  acquire`, grep the literal. The plan's default is the literal `claim-issue.sh`
  form (these consumers have no need for the fix-issues indirection). Either way
  the sentinel greps the EXISTING script name → no rename → zero existing-conformance
  churn. Defends the #729 accidental-revert class.

### Design & Constraints

- **PIPELINE_ID prerequisite (C1/M1).** No consumer may acquire before a non-empty
  PIPELINE_ID and a bare-integer issue number exist in scope. /do: acquire INSIDE
  the mode files after `do.${TASK_SLUG}`; /investigate: synthesize
  `investigate.issue-$N`; /quickfix: reuse `quickfix.$SLUG`.
- **Single sprint-id rule (all three):** `--sprint-id "$PIPELINE_ID"` (they have
  no sprint). Acquire shape identical across the three.
- **Issue-number normalization:** strip `#`/quotes to a bare positive integer
  before passing to `claim-issue.sh` (it rejects non-numeric at
  validate_issue_number:80-95, exit 2).
- **Foreign (exit 10) → STOP this invocation** with "issue #N is being worked by
  another pipeline; declining" — NOT "next candidate" (one-shot, not a sprint
  loop). Exit 11 → fs-error + stop. Exit 2 → internal bug → stop + surface.
- **Release placement (verified current sites):** investigate — success-path bash
  release block at Report + an explicit per-STOP prose release at every abandon
  point (no single bash terminal). /do worktree/direct — Phase 5 Report + error
  exits (NOT Phase 4 Land). /do PR — finalize block at pr.md:433-438 (regardless of
  created/merged) + INLINE release before the post-acquire-pre-finalize early exits
  (pr.md:153/157/274). /quickfix — post-/land-pr finalize + abandon sites; NO
  HOLD-on-created.

### Acceptance Criteria

- Each consumer establishes a non-empty PIPELINE_ID and a bare-integer issue
  number BEFORE its acquire; the acquire never runs with `--pipeline-id ""`.
- Each consumer's relevant file (per W2.6 placement) has a `claim-issue.sh acquire`
  before the work and a `claim-issue.sh release` at the terminal/abandon sites,
  including /do PR's inline releases before pr.md:153/157/274.
- New conformance sentinels in `tests/test-skill-conformance.sh` pass and would
  FAIL if a future edit drops the wiring.
- A second concurrent invocation of `/do --force #N` / `/investigate #N` against
  an already-claimed N stops with the "being worked by another pipeline" message.
- `/do` non-auto worktree/direct run releases the claim at Phase 5 Report (proven
  by claim dir gone afterward); a /do PR early-exit at pr.md:153/157/274 leaves NO
  leaked claim (proven by claim dir gone after the simulated early exit).
- `bash tests/run-all.sh` green; version bumps + mirrors present.

### Dependencies

Phase 1 (the scripts must already tolerate self-re-entry so a consumer's own
defensive re-acquire — e.g. /quickfix re-running after a transient — returns 0).
Lands its own PR.

---

## Phase 3 — run-plan issue-claim (execution-window protection) + operator-stop sweep + optional :597 cleanup

### Goal

When a plan's frontmatter has `issue: N`, `/run-plan` acquires `issue-<N>` at plan
start (alongside its plan claim) and holds it for the plan's FULL lifetime,
releasing only at the plan's terminal release points. Issue-foreign at start is
WARN-and-PROCEED (never abort, never leak the plan claim). Add an `issue-*` arm to
the operator-stop sweep so the issue claim is released on `/run-plan stop`.
Optionally shed the now-redundant `:597` self-decline prose. This is the #803
execution-window protection.

### Work Items

- [ ] **W3.1 — Parse `issue: N` from plan frontmatter, normalized to a bare
  integer.** Where `/run-plan` reads the plan (it derives `PLAN_SLUG`/`TRACKING_ID`
  from the plan file at SKILL.md:429), extract `issue:` line(s) from frontmatter.
  **Read from `$PLAN_FILE_FOR_READ`** (the PR-mode-worktree-aware read-authority
  var mandated at SKILL.md:391-413, "every subsequent plan read MUST use
  $PLAN_FILE_FOR_READ"), NOT bare `$PLAN_FILE`. **Strip `#` and surrounding
  quotes to a bare integer** — the existing Close-linked-issue parser tolerates
  `issue: 42` AND `issue: "#42"` (execute-phase.md:1341-1342); reuse/align with
  that same normalization rather than introducing a second divergent parser, since
  `claim-issue.sh validate_issue_number` (claim-issue.sh:80-95) rejects
  non-numeric input with exit 2. Support multiple `issue:` values → multiple
  issue claims.
- [ ] **W3.2 — Acquire `issue-<N>` in the existing acquire fence** (SKILL.md:587-
  602), right after the plan-claim acquire, using `bash <claim-issue.sh> acquire
  "$N" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"` (with `$N` the
  bare integer from W3.1). Because Phase 1 gave claim-issue.sh self-re-entry, a
  chunked re-fire re-acquiring the same issue returns 0 (the stable
  `run-plan.<slug>` pipeline_id matches). **rc handling (M2 DESIGN CALL — DECIDED,
  DIFFERENT from the plan-claim arm):**
  - rc=0 → proceed (held or self-re-entry).
  - **rc=10 → WARN-and-PROCEED.** Log loudly: "issue #N is claimed by another
    pipeline; proceeding with plan execution, issue claim NOT held." Then CONTINUE
    the plan. Do NOT `exit 0`-decline (that is the plan-claim arm's behavior;
    mirroring it would let a stale issue claim abort a legitimately-run plan). Do
    NOT release the just-won PLAN claim (it stays held — no plan-claim leak).
  - rc=11 → Failure Protocol (fs error). rc=2 → internal bug (un-stripped `#N`) →
    STOP + surface.
  Rationale recorded: #739 removed auto-expiry; a possibly-stale issue claim must
  not block a deliberately-run plan. The plan owns the plan.
- [ ] **W3.3 — Release `issue-<N>` ONLY at the plan's terminal release points**
  (the SAME sites as the plan-claim release, NOT "around `gh issue close`" — the
  close at execute-phase.md:1352 is NOT adjacent to the release at :1600):
  execute-phase.md:1600-1601 (terminal merge), the already-complete no-op at
  :1203, AND subcommands/stop-next-status.md (operator-stop). NEVER release
  per-phase. Per-phase `set-phase` on the PLAN claim is unaffected; there is NO
  per-phase issue-claim touch. **Each issue release uses
  `claim-issue.sh release "$N" --require-pipeline "$PIPELINE_ID"`.**
- [ ] **W3.4 — Add an `issue-*` arm to the operator-stop release loop (M2/M3
  FIX).** `subcommands/stop-next-status.md`'s release loop (`:124-165`) iterates
  `"$CLAIMS_ROOT"/plan-*` ONLY and gates on `pipeline_id` starting `run-plan.`;
  its comment at :145-147 explicitly assumes fix-issues uses `issue-*/`, so it
  STRUCTURALLY never sweeps the `issue-*/` dirs that run-plan now owns. Add a
  PARALLEL loop (or widen the glob) over `"$CLAIMS_ROOT"/issue-*` that releases
  each `issue-<N>` whose `pipeline_id` starts `run-plan.` via
  `claim-issue.sh release <N> --require-pipeline <pid>` — mirroring the existing
  `plan-*` loop's pipeline-id guard, mismatch-skip (exit 12), and tally. Without
  this, run-plan's issue claim leaks on `/run-plan stop`. Update the loop's tally
  message to count released/skipped issue claims too.
- [ ] **W3.5 — Multi-issue handling:** loop acquire over all parsed `issue:`
  values at start (each with its own WARN-and-PROCEED on rc=10); loop release over
  them at the terminal sites and in the operator-stop sweep.
- [ ] **W3.6 — Optional `:597` prose cleanup (D8).** The PLAN-claim rc=10 → decline
  arm STAYS (now correct: foreign-only). Optionally simplify the surrounding prose
  at SKILL.md:580-602 that hand-waves about same-pipeline re-acquire, since Phase 1
  makes self-re-entry return 0. Do NOT remove the plan-claim decline arm. (The new
  ISSUE-claim arm is the WARN-and-PROCEED arm from W3.2 — distinct from the plan
  arm.)
- [ ] **W3.7 — Version bump + mirror** `run-plan`.
- [ ] **W3.8 — Add a NEW positive conformance assertion (do NOT weaken the
  existing one).** `test-plan-claim-conformance.sh:71-94` asserts `claim-plan.sh
  acquire` precedes `### Execution` — leave it UNTOUCHED (still true: the new
  issue-claim acquire sits in the same fence and doesn't move the plan-claim
  acquire). ADD a separate positive assertion that, when run-plan's acquire fence
  is present, an `issue-<…>`/`claim-issue.sh acquire` appears in the fence and an
  `issue-*` arm appears in the operator-stop loop — if a clean static check
  exists; otherwise cover via a behavioral test fixture (acquire-window +
  operator-stop-release of an issue claim).

### Design & Constraints

- **LIFETIME RULE (verbatim):** the issue claim is acquired ONCE at plan start,
  **NEVER released per-phase**, persists across idle gaps between chunked fires
  (filesystem + no-TTL + self-re-entry make this automatic), released ONLY at the
  plan's terminal release points (terminal merge :1600-1601, no-op :1203,
  operator-stop) — NOT "around `gh issue close`" (:1352 is not adjacent). Multi-issue
  plans → multiple issue claims. Phases do NOT individually claim.
- **ISSUE-FOREIGN-AT-START = WARN-and-PROCEED (NOT abort, NOT plan-claim leak).**
  The issue arm is DELIBERATELY different from the plan-claim rc=10 `exit 0`
  decline arm. A stale issue claim must never block a deliberately-run plan, and
  the plan claim (legitimately won) is never released on the issue-foreign path.
- **Same pipeline_id** as the plan claim (`run-plan.<slug>`), `--sprint-id
  "$PIPELINE_ID"`. Issue number normalized to a bare integer (strip `#`/quotes).
- **Operator-stop must sweep `issue-*` too** (the plan-* loop is structurally
  blind to issue-* dirs).
- **No conformance weakening** (NEVER loosen an assertion to pass; ADD positive
  assertions).

### Acceptance Criteria

- A plan with `issue: N` (incl. `issue: "#N"`) frontmatter acquires `issue-<N>`
  (bare integer) at plan start and the claim dir persists across a simulated
  chunked-fire gap (release happens only at terminal merge).
- When `issue-<N>` is already foreign-held at plan start, run-plan logs the WARN
  and PROCEEDS; the plan claim is NOT released (still present) and the plan runs.
- A concurrent `/fix-issues` sees the issue's in-flight claim (filtered out by
  its existing `filter-in-flight-issue-claims.sh`).
- The issue claim is released at the terminal merge site (claim dir gone after
  plan completion), alongside the plan claim.
- `/run-plan stop` releases run-plan-held `issue-<N>` claims (claim dir gone after
  stop), via the new `issue-*` arm in the stop loop.
- `test-plan-claim-conformance.sh` passes UNCHANGED; the new positive assertion
  (W3.8) passes; `bash tests/run-all.sh` green.

### Dependencies

Phase 1 (self-re-entry must exist so the chunked re-fire's issue re-acquire
returns 0). Independent of Phase 2. Lands its own PR.

---

## Phase 4 — CLAUDE_TEMPLATE recursive claim discipline + docs

### Goal

Land the cross-cutting "claim before working a tracked work-item" rule in
`CLAUDE_TEMPLATE.md` (auto-loaded into every consumer's
`.claude/rules/zskills/managed.md`), re-render, and document the self-re-entry
contract in the twins' owner-skill docs.

### Work Items

- [ ] **W4.1 — Add a rule section to `CLAUDE_TEMPLATE.md`** (plain prose, resolved-
  variable discipline; introduce NO unsubstituted `{{...}}` token — the managed-
  rules renderer raises on leftover `{{[A-Z_]+}}` tokens). Text to capture:
  > Claim any tracked work-item (issue or plan) before working it; the claim is
  > held for the work's full lifetime INCLUDING idle gaps, and released only on
  > resolve/abandon, NEVER per-step. The discipline applies recursively: a
  > pipeline holding a plan claim that works the plan's issue ALSO holds the issue
  > claim. Foreign-held (acquire exit 10) → decline (one-shot consumers) or
  > WARN-and-proceed (a plan whose linked issue is foreign-held still runs — the
  > plan owns the plan); self-re-entry (exit 0) → proceed; there is NO TTL —
  > release is always explicit. Issues are claimed via `claim-issue.sh`, plans via
  > `claim-plan.sh`; both are ownership-aware (they recognize the caller's own
  > claim and return success on re-acquire).
- [ ] **W4.2 — Re-render `.claude/rules/zskills/managed.md`** via the documented
  path (`/update-zskills --rerender`, which runs `scripts/render-managed-rules.py`
  — confirmed in update-zskills SKILL.md:31-35 / Step D). Do NOT hand-edit
  `managed.md`.
- [ ] **W4.3 — Confirm `tests/test-managed-md-up-to-date.sh` passes** (the
  conformance gate keeping TEMPLATE and managed.md in sync).
- [ ] **W4.4 — Document the self-re-entry contract** in the twins' owner-skill
  docs or a reference file — e.g. a short `### Self-re-entry` note in each twin's
  header (already done in Phase 1 W1.5) PLUS a sentence in the relevant skill
  reference (`skills/fix-issues` / `skills/run-plan` reference docs, or
  `docs/skills/*`). Note the helper at
  `skills/create-worktree/scripts/claim-self-reentry.sh` and the exit-code
  contract.
- [ ] **W4.5 — Version bump + mirror** any skill whose bundle docs changed
  (create-worktree / fix-issues / run-plan as applicable). CLAUDE_TEMPLATE.md is
  not a skill (no version bump); the render + sync test is its gate.

### Design & Constraints

- **Plain prose / resolved-variable discipline.** NO unsubstituted `{{...}}`
  token (renderer raises). No hardcoded consumer literals (`npm run test:all`,
  etc.) — obey the skill-file hardcode discipline if any fence is added.
- **Recursive claim rule** stated verbatim per W4.1, including the
  decline-vs-WARN-and-proceed distinction between one-shot consumers and a plan
  whose linked issue is foreign-held.
- Re-render via the documented path; never hand-edit `managed.md`.

### Acceptance Criteria

- `CLAUDE_TEMPLATE.md` contains the recursive claim-discipline rule.
- `.claude/rules/zskills/managed.md` re-rendered and
  `tests/test-managed-md-up-to-date.sh` passes.
- `render-managed-rules.py` does not raise (no stray `{{...}}`).
- Self-re-entry contract documented in the twins' docs/reference.
- `bash tests/run-all.sh` green.

### Dependencies

Phases 1-3 (the rule describes behavior those phases implement; documenting it
before the behavior exists would be a phantom contract). Lands its own PR.

---

## Explicitly Out of Scope

- **`/fix-issues`: NO changes.** It already calls `claim-issue.sh`, so it gains
  self-re-entry free via Phase 1 (inert for it — fresh per-fire pipeline_id never
  self-collides — harmless). There is no fix-issues migration.
- **No `/claim-work-item` skill, no dispatch wrapper.** A future operator
  `/claims` management skill is unneeded: the dashboard already shows claim chips
  and ad-hoc release is a `claim-*.sh release <id> --require-pipeline <id>`
  one-liner.
- **#808** (plan-scale skip decisions not persisted) — separate filed issue, not
  this plan.
- **Drafting-window race** (a `/fix-issues` cron grabbing an issue before the
  `/run-plan` for it exists) — covered by #808's queue hygiene, not here.

## Constraints (zskills)

- NO jq — Python stdlib json (or bash `BASH_REMATCH`); `ZSKILLS_PYTHON`
  precedence. The helper's claim.json read uses the `try/except → empty` reader
  (release-style), NOT bare `json.load()` (set-phase-style).
- MAIN_ROOT via `git rev-parse --git-common-dir` parent — NEVER `$PWD` (resolved
  by the caller; the helper operates on the absolute claim_dir it's handed).
- Issue numbers passed to `claim-issue.sh` MUST be bare positive integers (it
  rejects `#`/quotes at validate_issue_number:80-95).
- No consumer acquires before a non-empty PIPELINE_ID and a bare-integer issue
  number exist in scope (the C1/M1 placement rule).
- Every edited skill bumps `metadata.version` (date `America/New_York` + content
  hash via `scripts/skill-content-hash.sh`) + re-mirror via
  `scripts/mirror-skill.sh`.
- New script behavior needs conformance coverage (`tests/test-claim-self-
  reentry.sh` + the per-consumer sentinels + the new run-plan positive assertion).
- The helper is a directly-authored skill script → NOT added to
  `script-ownership.md` / STALE_LIST / tier1-shipped-hashes.txt — same treatment
  as `claim-issue.sh`/`claim-plan.sh` (verified unregistered:
  `grep -n claim script-ownership.md` → 0 hits).
- NEVER weaken a conformance assertion to pass; add positive assertions instead.

## Plan Quality

**Process.** Authored via /draft-plan-equivalent (single-author design "B" with
the no-wrapper / self-re-entry-helper / 4-phase structure pre-settled), then
subjected to one adversarial review round: a reviewer pass (impl-correctness only)
and a devil's-advocate pass (impl-time concreteness attack). All findings were
verify-before-fix re-anchored against the worktree files (line cites drifted
slightly from the reviews and were re-confirmed) and applied. **Converged** — 0
substantive issues and 0 new gaps remain after the round.

**Round history.**

| Round | Reviewer findings | DA findings | Disposition |
|-------|-------------------|-------------|-------------|
| 1 | 3 MEDIUM, 5 LOW, 7 confirmations | 2 CRITICAL, 3 MAJOR, 2 MINOR, 2 sound | All 8 reviewer + 7 DA findings Verified & Fixed; settled design untouched |

Key fixes landed: PIPELINE_ID/issue-number availability for /do + /investigate
(acquire moved into mode files / synthesized pid — C1=M1); /do PR-mode
inline-release before post-acquire early exits (C2); operator-stop `issue-*` sweep
arm added (M2/M3 reviewer); issue-foreign-at-start = WARN-and-PROCEED, never abort,
never leak the plan claim (DA M2 design call); `issue:` `#`/quote stripping to a
bare integer reusing the existing parser (reviewer M3); helper try/except-or-empty
claim.json reader for malformed JSON (DA m1); path/citation, read-authority var,
sentinel-shape, and adjacent-vs-distant-release-site corrections (LOW/MINOR).
