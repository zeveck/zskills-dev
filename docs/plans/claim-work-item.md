---
issue: 803
title: Shared work-item claim primitive (claim-work-item.sh)
created: 2026-05-29
status: active
---

# Plan: Shared work-item claim primitive (claim-work-item.sh)

> **Landing mode: PR** — `.claude/zskills-config.json` has `main_protected: true`,
> so every phase works in a named worktree on a feature branch and lands via
> `/land-pr`. No commit/cherry-pick to main.

## Overview

Today only `/fix-issues` claims a GitHub issue before working it
(`skills/fix-issues/scripts/claim-issue.sh` → `.zskills/claims/issue-<N>/`), and
only `/run-plan` claims a plan (`skills/run-plan/scripts/claim-plan.sh` →
`.zskills/claims/plan-<slug>/`). When `/do`, `/quickfix`, or `/investigate` work
a GitHub issue (`/do` and `/quickfix` only via their `--force` triage override;
`/investigate` natively), they make **no claim** — so a concurrent `/fix-issues`
cron can grab the same issue and double-work it. Observed live on #802, which
required a manual `claim-issue.sh acquire` before dispatch.

This plan introduces ONE shared entry point — a `claim-work-item.sh` **script**
(not a new model-facing skill) — that the three unwired consumers call to claim
an issue or a plan. It dispatches by kind to the two existing,
individually-tested scripts and adds the one genuinely-new behavior nobody
implements today: **ownership-aware self-re-entry** (re-acquiring your own claim
returns success instead of a foreign-held error). The cross-cutting "claim
before you work a tracked work-item; release on resolve" discipline lands in
**CLAUDE_TEMPLATE.md** (the propagating surface), with per-skill specifics in
each consumer's SKILL.md and a conformance sentinel per consumer (the #729
accidental-revert defense).

The smallest correct design is **dispatch, not merge**: a thin wrapper that
routes `acquire | release | is-stale | set-phase` to claim-issue.sh /
claim-plan.sh by kind, preserving each script's tested contract and on-disk
schema, while presenting callers a single interface.

**Scope honesty — what "ONE way to claim" means here (acceptance interpretation).**
This plan does NOT achieve full convergence of all five claim sites onto one
call path. It closes the *actual* gap (the three unwired ad-hoc consumers) and
deliberately leaves the two batch callers on their direct scripts:

- **In scope:** `/do`, `/quickfix`, `/investigate` acquire/release through the
  shared wrapper. These are the consumers that make NO claim today (the bug).
- **Out of scope (D7):** `/fix-issues` keeps calling `claim-issue.sh` directly
  and `/run-plan` keeps calling `claim-plan.sh` directly. Migrating them is a
  named follow-up, not part of this plan — see Out of Scope. Because the wrapper
  *delegates to the very same two scripts*, there is no on-disk or behavioral
  *divergence* between the wrapper path and the direct path (identical dirs,
  schemas, exit codes). "One way" is therefore met as *one shared on-disk claim
  protocol every caller participates in*, not as *one identical function call in
  every skill*. The plan does not claim the stronger form.
- **`/run-plan` already satisfies #803's acceptance natively.** #803's
  acceptance line names `/run-plan` among the skills that must "claim a
  work-item before working it and release on resolve." `/run-plan` *already
  does both today*: it acquires the plan claim at `run-plan/SKILL.md:587-602`
  (`claim-plan.sh acquire`) and releases at its terminals
  (`modes/execute-phase.md:1199-1203` no-op re-entry, `:1599-1601` terminal
  merge, `subcommands/stop-next-status.md:154` operator stop). So deferring
  `/run-plan` migration is NOT "failing to deliver a named requirement" — the
  requirement is pre-met. (The issue's *Problem* paragraph erroneously lists
  `/run-plan` among skills that "do NOT claim"; that is an author error —
  `/run-plan` demonstrably claims and releases.) The separate
  `/run-plan:597` same-pipeline re-acquire conflation (D7) is a latent bug,
  not the acceptance bar, and is a named follow-up.

- **Enforcement is advisory for the three new consumers (D6).** Unlike
  `/fix-issues` (whose `block-fix-issue-unclaimed.sh` PreToolUse hook
  mechanically blocks an unclaimed `fix-issue-NNN` push), the new consumers'
  claim discipline is enforced ONLY by prose + CLAUDE_TEMPLATE + a
  text-presence conformance sentinel. There is NO runtime guarantee the agent
  actually runs `acquire`; the sentinel defends the *wiring text* against
  accidental revert (#729 class), not the *runtime behavior*. A broadened hook
  is an explicit deferred follow-up. This is stated plainly so the plan does not
  oversell mechanical enforcement.

## Locked Decisions

### D1 — Shared **script**, not a new skill. `claim-work-item.sh`, owner `create-worktree`. NOT registered in script-ownership.md / STALE_LIST / hash file.

The primitive is `skills/create-worktree/scripts/claim-work-item.sh` (a script
owned by the `create-worktree` skill), NOT a `/claim-work-item` SKILL.

**Rationale.** A claim primitive is called *by other skills*, never typed by a
human or invoked by the model as a slash command — so a SKILL would add
slash-command surface nobody needs and incur full new-skill ceremony (docs page,
per-skill conformance pins, invocation-flag decisions). The correct precedent is
**`claim-issue.sh` / `claim-plan.sh` themselves**: both are skill-owned scripts
authored directly inside their owner skill's `scripts/` dir, invoked across skill
boundaries, and **NOT registered** in `script-ownership.md`, `STALE_LIST`, or
`tier1-shipped-hashes.txt`. `claim-work-item.sh` is in exactly that category — a
script authored directly inside an owner skill, never originating at top-level
`scripts/`. We co-locate it under `create-worktree` because `claim-plan.sh`
already reaches across a skill boundary to call `create-worktree`'s
`sanitize-pipeline-id.sh`; co-locating the new wrapper there keeps the sanitizer
dependency in-skill and matches the cross-skill-script pattern. The issue's "a
NEW `/claim-work-item` skill warrants `/draft-plan`" note is satisfied two ways:
(a) this very plan IS that adversarial review, and (b) a script is even lighter
than a skill and triggers no new-skill review requirement at all.

**CRITICAL — do NOT touch the migration registry (corrects round-1 error).** The
earlier draft instructed adding a `claim-work-item.sh` row to
`script-ownership.md`, bumping `Total: 31 → 32`, and adding it to `STALE_LIST` /
`tier1-shipped-hashes.txt`. That was **factually wrong about what the registry
tracks and would FAIL CI**. `script-ownership.md` (header lines 1-7) is the
authoritative table for scripts that **originate at top-level `scripts/` and
migrate INTO a skill** (parsed by `/run-plan` Phase 4 migration logic + the
`test-update-zskills-migration.sh` drift tests). `sanitize-pipeline-id.sh` is in
the registry *because it migrated from top-level into create-worktree* — it is
NOT a precedent for a directly-authored skill script. A brand-new script
authored directly at `skills/create-worktree/scripts/claim-work-item.sh` never
lived at top-level, so:
- Adding a doc row WITHOUT adding to `STALE_LIST` → `test-update-zskills-migration.sh`
  **case 6a FAILS** (Tier-1 names parsed from `script-ownership.md` are diffed
  against the `STALE_LIST` array in `update-zskills/SKILL.md:1531`).
- Adding to `STALE_LIST` → tells `/update-zskills` to *migrate a consumer's
  top-level `scripts/claim-work-item.sh`* that never exists, and the hash
  generator (which hashes `scripts/$name` at top-level) has nothing coherent to
  hash for **cases 6b/6c**.

Therefore: **claim-work-item.sh is NOT added to `script-ownership.md`,
`STALE_LIST`, or `tier1-shipped-hashes.txt`.** No count bump. No registry edit.
This is the same treatment claim-issue.sh / claim-plan.sh already receive.

**Rejected alternatives.**
- *New `/claim-work-item` SKILL* — adds a `/` command, docs/skills page,
  invocation-flag surface, and per-skill conformance pins for zero caller
  benefit. Cost > benefit.
- *Single merged `claim-resource.sh <kind> <key>` replacing both scripts* —
  `plans-claim-chip-parity.md` D1 rejected exactly this; merging would force
  re-validating both scripts' tested contracts and rewriting `/fix-issues` +
  `/run-plan` + their full conformance batteries in lockstep. Dispatch
  preserves the tested contracts untouched.

**Verification (reproduced this round):** `grep -n claim script-ownership.md` →
ZERO claim rows (claim-issue.sh / claim-plan.sh absent); `grep claim
tier1-shipped-hashes.txt` → rc=1 (none); `STALE_LIST` (`update-zskills/SKILL.md:1531-1564`)
has no claim entries; `script-ownership.md:1-7` header scope ("scripts under
`scripts/` … machinery that moves into a skill"); `test-update-zskills-migration.sh:422-510`
cases 6a/6b/6c. `grep -n 'sanitize-pipeline-id.sh' skills/run-plan/scripts/claim-plan.sh`
shows the existing cross-skill call that justifies the create-worktree owner.

### D2 — Wrapper = dispatch by kind. "Unification" is at the CALLER interface, not storage.

`claim-work-item.sh <subcommand> <kind> <id> [flags]` where `kind ∈ {issue, plan}`.
It **delegates** to claim-issue.sh / claim-plan.sh; it writes NO new
`claim.json`. Storage stays exactly `.zskills/claims/issue-<N>/claim.json`
(schema `{schema_version, pipeline_id, sprint_id, issue, started_at}`) and
`.zskills/claims/plan-<slug>/claim.json` (schema `{schema_version, kind:"plan",
slug, pipeline_id, started_at, current_phase}`).

**Rationale.** The dashboard's `collect.py` scans `.zskills/claims/` and matches
dir names against exactly two regexes (`^issue-(\d+)$`, `^plan-(.+)$`) and pulls
kind-specific fields (issue chip needs `sprint_id`; plan chip needs
`current_phase`). The two schemas are NOT identical supersets in practice — a
single unified `claim.json` would have to be kind-aware anyway. Delegation keeps
each existing reader, dir name, and schema byte-for-byte unchanged → zero
dashboard *schema* risk, zero collector edits. Callers get the unification
benefit (one entry point, one self-re-entry contract); storage divergence is
invisible to them.

**Caveat — sprint_id field *content* for non-sprint callers (see D8).** D2's
"byte-for-byte unchanged → zero dashboard risk" is about the *schema shape*, not
the field *values*. Because `/do`/`/quickfix`/`/investigate` have no sprint, the
`sprint_id` field for their issue claims carries a synthesized value (D8). The
schema shape is unchanged; the stored value will read like `do.<slug>` etc.
This is an accepted cosmetic (D8) — called out so D2 is not over-read as "the
dashboard is wholly unaffected." (Note: `collect.py` emits `sprint_id` into the
issues JSON, but `static/app.js` has no `claim.sprint_id` consumer today, so
there is no current visible chip label for it — see D8.)

**Verification:** `collect.py` `_CLAIM_DIR_RE`/`_PLAN_CLAIM_DIR_RE` (mechanism
research §4) and the explicit chip field allow-lists at `collect.py:1908-1916`
(issue) / `:1785-1793` (plan).

### D3 — Self-re-entry is the new behavior. Exact exit-code contract below.

On `acquire`, the wrapper first delegates to the underlying script. If that
returns **10 (EEXIST)**, the wrapper READS the stored `pipeline_id` from the
existing `claim.json` and compares it to the caller's `--pipeline-id`:
- **match → exit 0** (idempotent self-claim; the caller already owns it).
- **mismatch → exit 10** (genuinely foreign-held; caller declines/race-lost).
- **claim.json absent → exit 10** (never steal — see race note below).

This is the load-bearing new logic — neither underlying script reads the stored
`pipeline_id` at acquire time today, so a pipeline re-running `acquire` against
its OWN claim currently gets 10 identical to a foreign claim. `/run-plan`
SKILL.md:597 is the canonical example: its acquire fence has no same-pipeline
skip guard, so a chunked re-fire that re-reaches the fence self-declines (the
separate latent bug discussed in D7 — out of scope for this plan but the exact
class the wrapper's self-re-entry closes for the three new consumers).

**Race / TOCTOU notes (the absent-claim.json verdict is exit 10 for BOTH causes
— do NOT "fix" this to steal).** The delegate returns 10 purely from `mkdir
"$claim_dir"` hitting EEXIST, whether or not `claim.json` is present yet
(`claim-issue.sh:136` mkdir vs `:155-169` non-atomic later write). So
"dir-exists, claim.json-absent" arises from TWO causes, and exit 10 is the
correct, conservative verdict for **both**:
1. **Live mid-write peer** — a concurrent pipeline just won the `mkdir` but
   hasn't written `claim.json` yet. It owns the claim; decline.
2. **Dead-peer crash stub** — a pipeline crashed between `mkdir` and write.
   Declining is still correct: D4 forbids TTL/staleness-stealing, so a crash
   stub is cleared only by explicit `release`, never auto-reaped.
   Additionally, a **TOCTOU** exists between the delegate returning 10 and the
   wrapper opening claim.json: the holder could `release` (rm + rmdir) in that
   window, leaving claim.json absent for a now-FREE item → the wrapper declines
   a now-available item (spurious decline). This is **conservative (decline, not
   double-work)** and accepted. A future maintainer MUST NOT "fix"
   absent-claim.json → steal: that reintroduces the #739 mid-work-expiry bug.

**Wrapper exit-code contract (authoritative):**

| Exit | Meaning |
|------|---------|
| 0  | acquired (fresh) OR self-re-entry confirmed (already held by caller's pipeline_id) |
| 2  | usage error (bad/missing kind, missing required flags, bad id, kind×subcommand mismatch) — raised by the wrapper BEFORE dispatch, or propagated from the underlying script |
| 10 | foreign-held (claim exists, stored pipeline_id ≠ caller's, OR claim.json absent — never steal) |
| 11 | filesystem error (propagated from the underlying script's non-EEXIST mkdir/write failure) |
| 12 | release pipeline-id mismatch (propagated from the underlying script's `release --require-pipeline`) |

`release`, `is-stale` (issue only), `set-phase` (plan only) propagate the
underlying script's exit code and stdout/stderr unchanged (the wrapper adds
ownership logic ONLY to `acquire`; it adds kind×subcommand validation to all).

**Verification:** `claim-issue.sh:136-179` (acquire: 10 on bare EEXIST never
reading pipeline_id, 11 on non-EEXIST, 2 on missing flags `:115-119`);
`claim-issue.sh:210-224` / `claim-plan.sh:263-277` (the existing
`--require-pipeline` comparison → 12 the wrapper mirrors for the read-compare
step).

### D4 — NO TTL / heartbeat / sweep / refresh. Hard constraint from #684/#739.

The wrapper introduces no wall-clock expiry of any kind. Lifecycle is
acquire-at-pickup / release-at-resolve-or-abandon. Stale claims are cleared ONLY
by explicit `release` (caller on resolve/abandon) or manual operator `release`.
The wrapper exposes `is-stale` for the issue kind solely as the existing
crash-window race check (dir without claim.json > 30s); it adds no new staleness
concept. A persistent stale claim is an accepted, cheaper-than-mid-work-expiry
tradeoff (#739 risk-asymmetry analysis).

**Verification:** `claim-issue.sh:274-277` ("a live claim is never stale");
#684/#739 prior-art research §1.

### D5 — Walk-away release policy: release-on-resolve at a UNIVERSALLY-REACHED terminal point. PR-mode releases on resolution regardless of created/merged.

The wrapper provides acquire/release as separate calls against
filesystem-persistent claims. The hard constraint corrected this round: **the
release MUST sit at a code point reached on EVERY terminal exit of the
consumer's mode**, not behind an `AUTO_FLAG` gate. Per consumer:

- **`/investigate`** — single-shot, no PR lifecycle, commits in place: ONE
  release at the terminal point (Phase 5 success report AND the
  couldn't-reproduce / root-cause-unclear / fix-failed-twice abandon paths). No
  HOLD.
- **`/do` worktree/direct (Paths B/C)** — release in **Phase 5 Report**
  (`do/SKILL.md:859`), the universal terminal point reached on BOTH the
  `auto` (Phase 4 ran) and **non-`auto` (Phase 4 skipped)** exits, PLUS the
  verification-fail / task-too-big / push-fail error-handling exits
  (`do/SKILL.md:909`). Release is **NOT** placed in Phase 4 Land — Phase 4
  is gated `Only reached if AUTO_FLAG=1` (`do/SKILL.md:819`), so a
  Phase-4-only release would leak the claim forever on the dominant interactive
  (non-`auto`) path. (Corrects round-1 W2.2.)
- **`/do` PR mode (Path A) + `/quickfix`** — release in the post-`/land-pr`
  finalize, **release-on-resolution regardless of `created` vs `merged`** and on
  every abandon path. Do NOT copy `/fix-issues`'s `HOLD-on-created` arm.

**`/do every` / `auto` re-fire reconciliation (corrects round-1 D5/W2
contradiction).** `/do every` self-schedules, but each fire is a FRESH `/do
<description>` invocation that **re-runs the work** — it is NOT `/fix-issues`'s
HOLD-and-re-poll-a-specific-PR model. So for `/do`/`/quickfix` we deliberately do
NOT HOLD-on-created. The role of self-re-entry (D3 → exit 0) for these is
narrow and correct: in the *rare* window where a re-fire lands AFTER acquire but
BEFORE the release ran (e.g. mid-flight on the same item under the same
PIPELINE_ID), the re-acquire returns exit 0 (proceed) instead of a spurious
self-decline. It is NOT a HOLD mechanism. The duplicate-PR risk for a
one-shot-per-fire `/do`/`/quickfix` is bounded: a concurrent *foreign* fire must
re-pick the item in the narrow window between PR-resolution and release —
acceptable vs the guaranteed leak that HOLD-without-a-re-poll-loop would cause.

**Rationale.** This keeps the hard `/fix-issues` PR-mode HOLD constraint
untouched (out of scope) while giving the new consumers a release path that is
reached on every terminal exit and does not strand claims on the dominant path.

**Verification:** `do/SKILL.md:819` (Phase 4 gated on AUTO_FLAG=1),
`:860` (Phase 5 Report — universal terminal), `:910-925` (error-handling exits);
`skills/fix-issues/modes/pr.md:336-345` (HOLD-on-`created` we deliberately do
NOT copy); `/do` `every` self-scheduling (`do/SKILL.md:64-99`).

### D6 — Enforcement is PROSE + CLAUDE_TEMPLATE + conformance sentinel. NO new PreToolUse hook. Advisory-only for the three new consumers (stated, not papered over).

The existing `block-fix-issue-unclaimed.sh` only gates branches matching
`^fix-issue-NNN$`/`^fix/issue-NNN$` (`block-fix-issue-unclaimed.sh:174-183`;
all other branches `exit 0`); `/do` (`do/<slug>`), `/quickfix` (no worktree at
all — `git checkout -b` on main, `quickfix/SKILL.md:709,730`), and `/investigate`
(no worktree) all bypass it. We do NOT add a new hook. Instead the rule lands in
**CLAUDE_TEMPLATE.md** (auto-rendered into every consumer's
`.claude/rules/zskills/managed.md`), the per-skill acquire/release fences land in
each SKILL.md, and a **conformance sentinel** in `tests/test-skill-conformance.sh`
asserts each of the three consumers retains its `claim-work-item.sh ... acquire`
+ release wiring text.

**Explicit acceptance gap (do not oversell).** The sentinel asserts only the
*presence of the wiring text* — it is the #729 accidental-revert defense, not a
runtime guarantee. There is **no mechanical runtime enforcement** that the agent
actually runs `acquire` for the three new consumers; enforcement is **advisory**
(prose + CLAUDE_TEMPLATE + text-presence sentinel). This is weaker than
`/fix-issues`, whose hook mechanically blocks an unclaimed push. A broadened hook
(at minimum for `/do`, which DOES create a `do/<slug>` worktree) is an explicit
**deferred follow-up**, not part of this plan. We accept advisory-only here
because the dominant double-work source is the *cron* `/fix-issues` racing an
*interactive* ad-hoc run; the ad-hoc agent reading the CLAUDE_TEMPLATE rule +
running the prose acquire closes that, and a hook can only check claim
*existence*, not *ownership*, anyway.

**Verification:** `block-fix-issue-unclaimed.sh:174-183` (non-fix-issue branches
`exit 0`); `quickfix/SKILL.md:709,730` (`git checkout -b`, no create-worktree);
CLAUDE_TEMPLATE rule-home precedent prior-art §2a; #729 sentinel precedent §1.

### D7 — `/fix-issues` and `/run-plan` are NOT migrated. Wrapper is additive (new consumers only). `/run-plan` already meets the acceptance natively; its `:597` same-pipeline re-acquire conflation is a SEPARATE latent bug, left as a named follow-up.

`/fix-issues` keeps calling `claim-issue.sh` directly; `/run-plan` keeps calling
`claim-plan.sh` directly.

**Why deferring `/run-plan` is NOT a deferred hard part — it already satisfies
the acceptance (corrects round-1 + round-2 DA).** #803 names `/run-plan` among
the skills that must "claim a work-item before working it and release on
resolve." `/run-plan` *already does both today*, independent of this plan: it
acquires the plan claim at `run-plan/SKILL.md:587-602`
(`claim-plan.sh acquire`) and releases at its terminals — no-op re-entry
(`modes/execute-phase.md:1199-1203`), terminal merge (`:1599-1601`), and
operator stop (`subcommands/stop-next-status.md:154`). The acceptance bar for
`/run-plan` is therefore *pre-met*; not migrating it onto the wrapper does not
leave a named requirement undelivered.

**The `/run-plan:597` conflation is a SEPARATE latent bug, NOT something this
plan must fix.** The Overview/D3 cite `/run-plan SKILL.md:597` (rc=10 →
"in-flight by another pipeline; declined" + `exit 0`, no self-check) as a
real example of the self-vs-foreign conflation the wrapper's self-re-entry
fixes for the new consumers. Verified this round, including the DA's
falsifying trace: that conflation **IS reachable** within a single pipeline.
`finish auto` chunks one phase per cron fire under a stable
`pipeline_id` (`run-plan/SKILL.md:588`); the claim is acquired in fire 1 and
released only at the two terminals above — there is **no per-phase release**.
On the fire for phase N+1, Step 0's in-progress gate is a *tracker-counter*
defer (phase N+1 is not yet In Progress when its fire arrives), so Step 0 takes
its case-4 "Otherwise: proceed with normal preflight" path, which routes
straight back to the acquire fence at `:587-602`. That fence has **no
already-acquired-by-my-pipeline skip guard** and re-runs `claim-plan.sh
acquire`, which has zero self-recognition (`claim-plan.sh:184-199`) → rc=10
against its OWN held claim → `:597` declines and `exit 0`. So the earlier
"Step-0 makes `:597` unreachable / benign" reasoning was **FALSE**. This is a
genuine same-pipeline re-acquire bug in `/run-plan`, but it is **separate from
#803's acceptance** (which `/run-plan` already meets via its existing
claim+release wiring). Fixing it — by migrating `/run-plan` onto the wrapper's
self-re-entry, or by adding a same-pipeline skip guard at the `:587-602` fence —
is a **named follow-up** (migration would also break the plan-claim conformance
battery), NOT part of this plan and NOT a silent abandonment.

**Rationale (migration cost).** `tests/test-fix-issues-claim-conformance.sh`
test 4 (`:118-124`) greps for ≥2 `CLAIM_HELPER="...claim-issue.sh"` assignments
AND ≥2 `bash "$CLAIM_HELPER" acquire` invocations in `modes/sprint.md`; the
plan-claim battery has the parallel pins. Migrating either skill would break
both batteries and force lockstep rewrites of two complex, heavily-tested
skills for no #803-acceptance gain — they already claim correctly.

**Self-re-entry asymmetry is intentional.** `/do`-created and
`/fix-issues`-created claims are byte-identical and mutually readable/releasable
(shared dirs/schemas). A `/fix-issues` cron seeing a `/do`-held issue gets rc 10
and declines (correct: foreign). The asymmetry — `/fix-issues`/`/run-plan`
re-entering their OWN claim still get the conflate-as-foreign behavior — is the
named `:597` follow-up for `/run-plan` and is filtered upstream for
`/fix-issues` (its sprint loop skips already-claimed candidates before
acquiring). Self-re-entry is wrapper-only by design in this plan.

**Verification:** `run-plan/SKILL.md:587-602` (acquire fence, no self-skip
guard; `:597` rc=10 → exit 0; `:588` stable per-plan pipeline_id);
`modes/execute-phase.md:1199-1203,1599-1601` + `subcommands/stop-next-status.md:154`
(the only release terminals — no per-phase release); `claim-plan.sh:184-199`
(acquire has no self-recognition); `test-fix-issues-claim-conformance.sh:118-124`
(the two-pass grep — migrating breaks it).

### D8 — Synthesized sprint-id for non-sprint callers: `--sprint-id "$PIPELINE_ID"` (single rule). Dashboard cosmetic accepted.

`claim-issue.sh acquire` **REQUIRES** `--sprint-id` (`claim-issue.sh:115-119` →
exit 2 if absent). `/do`, `/quickfix`, `/investigate` have no sprint concept, so
they MUST synthesize one. **Single mandated rule (no implementer choice): pass
`--sprint-id "$PIPELINE_ID"`** for all three consumers — reuse the
already-sanitized PIPELINE_ID verbatim, so `sprint_id == pipeline_id` is a
recognizable "no real sprint" sentinel and the conformance sentinel can grep a
stable shape. (`claim-plan.sh acquire` does NOT require `--sprint-id` — the
wrapper rejects `--sprint-id` for `kind=plan`, exit 2.)

**Accepted dashboard cosmetic.** The synthesized value lands in `claim.json`'s
`sprint_id` and is emitted into the issues JSON / HTTP response by the dashboard
collector (`collect.py:1912`, `issue["claim"]["sprint_id"]`) as e.g.
`do.add-dark-mode`. There is **no current `app.js` chip consumer** of
`claim.sprint_id` (the only `sprint` references in `app.js` are unrelated
workspace-state machine states, `app.js:1366,2231`), so the synthesized value
is stored/emitted but not demonstrably rendered as a visible chip label today.
Either way it is an accepted cosmetic (a non-sprint value in a sprint-labeled
field), taken as the cost of reusing claim-issue.sh's required flag rather than
relaxing its tested contract. A dashboard "synthetic sprint" display tweak is
out of scope.

**Verification:** `claim-issue.sh:115-119` (sprint-id required);
`collect.py:1912` (emits `sprint_id` into the issue claim JSON);
`grep sprint static/app.js` → only workspace-state `"sprint"`, no
`claim.sprint_id` consumer; `run-plan/SKILL.md:592` (claim-plan acquire passes
only `--pipeline-id`).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| Phase 1 — Build `claim-work-item.sh` + self-re-entry + tests | ⬚ | | |
| Phase 2 — Wire `/do`, `/quickfix`, `/investigate` onto the wrapper | ⬚ | | |
| Phase 3 — CLAUDE_TEMPLATE rule + conformance sentinels + docs | ⬚ | | |

## Phase 1 — Build `claim-work-item.sh` + self-re-entry + tests

### Goal
Create the shared dispatch wrapper with ownership-aware self-re-entry, mirror it,
and ship a dedicated conformance + behavior test suite. No consumer is wired yet
— Phase 1 is independently verifiable in isolation. **No script-ownership.md /
STALE_LIST / hash-file edits** (D1).

### Work Items
- [ ] W1.1 — Create `skills/create-worktree/scripts/claim-work-item.sh`
  (executable, `#!/bin/bash`, `set -euo pipefail`). Header documents the
  delegation model, the D3 exit-code contract verbatim, the
  absent-claim.json-→-10 never-steal note (D3 race notes), and the no-jq /
  Python-precedence / MAIN_ROOT-via-`git rev-parse --git-common-dir`
  (never-`$PWD`) invariants.
- [ ] W1.2 — Implement subcommand dispatch: `acquire | release | is-stale |
  set-phase`, first positional after subcommand is `<kind>` ∈ `{issue, plan}`,
  second is `<id>`. Validate kind×subcommand compatibility **in the wrapper,
  BEFORE dispatch**, emitting the wrapper's own message (so exit 2 is
  deterministic, not a delegate fall-through artifact — reviewer #5):
  `is-stale` ⇒ `issue` only; `set-phase` ⇒ `plan` only; unknown
  subcommand/kind ⇒ exit 2. `list` is NOT exposed (reviewer #6 — no consumer
  needs it; callers can hit the delegates' `list` directly).
- [ ] W1.3 — Locate the delegate scripts portably (plugin lane vs source-tree
  mirror), mirroring `claim-plan.sh`'s `_locate_sanitizer` precedence pattern:
  try `$CLAUDE_PROJECT_DIR/.claude/skills/{fix-issues,run-plan}/scripts/...`,
  then `$REPO_ROOT/skills/...` (source-tree tests). Hard-error → exit 2 if
  neither resolves.
- [ ] W1.4 — Implement `acquire` self-re-entry (D3) with a **step-by-step
  MAIN_ROOT/path spec** (reviewer #3, DA D8):
  1. Pass through to the delegate (issue: forward `--pipeline-id` +
     `--sprint-id`; plan: forward `--pipeline-id`, reject `--sprint-id` → exit 2).
  2. If delegate rc ≠ 10, return rc unchanged (0/2/11 propagate).
  3. On rc == 10: resolve MAIN_ROOT with the **IDENTICAL algorithm the delegates
     use** — `git rev-parse --git-common-dir` then take its parent; **hard-error
     → exit 2, NEVER fall back to `$PWD`** (copy `resolve_main_root`'s body from
     the delegate verbatim so there is zero divergence — DA D8).
  4. Construct the claim dir: `issue` → `${MAIN_ROOT}/.zskills/claims/issue-<N>`;
     `plan` → first run `<slug>` through create-worktree's
     `sanitize-pipeline-id.sh` (the delegate sanitizes before path construction;
     an unsanitized slug would read the wrong path and misclassify — reviewer #3),
     then `${MAIN_ROOT}/.zskills/claims/plan-<sanitized-slug>`.
  5. If `claim.json` absent → exit 10 (never steal — D3). Else read stored
     `pipeline_id` via Python stdlib json; equal to caller's `--pipeline-id` →
     exit 0, else exit 10.
- [ ] W1.5 — Implement `release`, `is-stale`, `set-phase` as pure pass-through to
  the delegate (exit code + stdout/stderr preserved), AFTER the W1.2 wrapper-side
  kind×subcommand validation.
- [ ] W1.6 — Mirror via `bash scripts/mirror-skill.sh create-worktree`; bump
  `skills/create-worktree/SKILL.md` `metadata.version` (today's ET date + fresh
  content hash via `scripts/skill-content-hash.sh`).
- [ ] W1.7 — **(REMOVED — corrects round-1 BLOCKER#1 + DA D1.)** Do NOT add a
  row to `script-ownership.md`, do NOT bump `Total: 31 Tier 1`, do NOT touch
  `STALE_LIST` or `tier1-shipped-hashes.txt`. `claim-work-item.sh` follows the
  same un-registered treatment as `claim-issue.sh` / `claim-plan.sh` (D1). The
  test that confirms this absence is W1.9.
- [ ] W1.8 — New test `tests/test-claim-work-item-script.sh`: behavior matrix
  (see Acceptance) in a temp git repo with the delegates **staged** (see Design
  → "Test harness delegate-staging", DA D12). MUST include a self-re-entry case
  run **from a worktree cwd** (not just the main repo), since that is the only
  place a MAIN_ROOT-resolution divergence would manifest (DA D8).
- [ ] W1.9 — New test `tests/test-claim-work-item-conformance.sh`: source +
  mirror present/executable/byte-equal; header documents the exit contract; no
  TTL/heartbeat/sweep/refresh tokens; no jq; Python-precedence line present;
  MAIN_ROOT resolved via `git rev-parse --git-common-dir` (no `$PWD` acquire-time
  fallback); **and assert `claim-work-item.sh` is absent from
  `script-ownership.md`, `STALE_LIST`, and `tier1-shipped-hashes.txt`** (locks
  the D1 decision against a future erroneous registration). **Note (round-2 DA
  NIT-1):** the repo-wide hardcode deny-list scan in
  `test-skill-conformance.sh:2118` enumerates only `skills/**/scripts/*.py` —
  NOT `*.sh` — so a `.sh` wrapper is NOT subject to that gate. The
  Python-precedence / no-hardcode assertions here are therefore this test's own
  belt-and-suspenders hygiene, NOT a mirror of an external repo gate; keep them,
  but do not imply they satisfy an external conformance requirement.
- [ ] W1.10 — Run `bash tests/run-all.sh`; capture to
  `$TEST_OUT/${TEST_OUTPUT_FILE:-.test-results.txt}`; all suites green.

### Design & Constraints
- **CLI:** `claim-work-item.sh acquire <kind> <id> --pipeline-id <id> [--sprint-id <id>]`
  (`--sprint-id` REQUIRED iff kind=issue; REJECTED → exit 2 if kind=plan);
  `release <kind> <id> [--require-pipeline <id>]` (delegate to claim-issue.sh
  where `--require-pipeline` is optional, claim-plan.sh where it is required —
  the wrapper passes the flag through verbatim and does NOT relax claim-plan's
  requirement);
  `is-stale issue <N>`; `set-phase plan <slug> --require-pipeline <id> --current-phase "<str>"`.
  **No `list`** (reviewer #6).
- **Exit contract:** exactly D3's table. `acquire` is the ONLY subcommand the
  wrapper adds ownership logic to; kind×subcommand validation applies to all and
  is wrapper-side, pre-dispatch (reviewer #5).
- **Storage (D2):** wrapper writes NO claim.json; the delegate owns all writes.
- **MAIN_ROOT (reviewer #3, DA D8):** the wrapper's self-re-entry read MUST
  resolve MAIN_ROOT with the IDENTICAL function body as the delegates
  (`git rev-parse --git-common-dir` parent, hard-error → exit 2, NEVER `$PWD`).
  For plan kind, sanitize the slug via create-worktree's sanitizer BEFORE
  constructing `plan-<slug>`.
- **Test harness delegate-staging (DA D12):** the behavior-matrix test in W1.8
  runs in a temp repo, but the wrapper locates delegates via
  `$CLAUDE_PROJECT_DIR/.claude/skills/{fix-issues,run-plan}/scripts/...` then
  `$REPO_ROOT/skills/...`. A pristine temp repo has neither → every acquire would
  return exit 2. The test MUST stage the real `claim-issue.sh` / `claim-plan.sh`
  **and** `sanitize-pipeline-id.sh` into the temp repo's `skills/.../scripts/`
  layout AND export `REPO_ROOT`/`CLAUDE_PROJECT_DIR` pointing at it. **Precedent
  caveat (round-2 reviewer NIT-3):** `test-plan-claim-script.sh:15-16,51-57` is
  a *partial* template only — it runs `claim-plan.sh` **in place** against the
  real `$REPO_ROOT` (`CLAIM_SH=$REPO_ROOT/skills/run-plan/scripts/claim-plan.sh`)
  and stages only the cross-skill *sanitizer* into the scratch dir, NOT the
  delegates themselves. This plan's requirement is STRONGER (stage both delegates
  + the sanitizer into an isolated temp repo so the wrapper's own
  delegate-location precedence is exercised) — do NOT assume the cited test is a
  copy-paste template for full delegate-staging; borrow its sanitizer-staging +
  `CLAUDE_PROJECT_DIR` export idiom and extend it. "Fresh repo" in the ACs means
  "temp repo with delegates staged," NOT pristine.
- **Python:** `PYTHON="${ZSKILLS_PYTHON:-$(command -v python3 || command -v python)}"`;
  no jq. **No `2>/dev/null`** on the fallible delegate calls whose rc matters.
- **No TTL/heartbeat/sweep/refresh** (D4) — tokens absent (asserted by W1.9).

### Acceptance Criteria
(Each runs in the staged temp repo per Design → delegate-staging; "fresh"
means a clean `.zskills/claims/` within that staged repo.)
- `acquire issue 5 --pipeline-id P --sprint-id S` → exit 0, creates
  `.zskills/claims/issue-5/claim.json` with `{pipeline_id:"P", sprint_id:"S",
  issue:5, ...}`.
- Re-run identical `acquire issue 5 --pipeline-id P --sprint-id S` → **exit 0**
  (self-re-entry), claim.json unchanged.
- `acquire issue 5 --pipeline-id Q --sprint-id S` (different pipeline) → **exit 10**.
- **Crash-window:** create `.zskills/claims/issue-5/` then remove its claim.json;
  `acquire issue 5 --pipeline-id P --sprint-id S` (**flags PRESENT** — reviewer
  #4: omitting them returns exit 2 before mkdir, not 10) → **exit 10**.
- **Worktree-cwd self-re-entry (DA D8):** from a `git worktree` of the staged
  repo, after `acquire issue 5 --pipeline-id P --sprint-id S` from main, re-run
  the same acquire FROM the worktree cwd → **exit 0** (proves MAIN_ROOT resolves
  to the shared common-dir parent, not the worktree's `$PWD`).
- `acquire plan my-slug --pipeline-id P` → exit 0, creates
  `.zskills/claims/plan-my-slug/claim.json`; re-run same → exit 0; different
  pipeline → exit 10.
- `acquire plan x --pipeline-id P --sprint-id S` → **exit 2** (sprint-id illegal
  for plan); `acquire issue 5 --pipeline-id P` (no sprint-id) → **exit 2**.
- `release issue 5 --require-pipeline Q` (wrong pipeline) → **exit 12**, claim
  intact; `release issue 5 --require-pipeline P` → exit 0, dir gone.
- `is-stale plan x` → **exit 2** (wrapper-side wrong-kind reject, own message);
  `set-phase issue 5 ...` → **exit 2** (wrapper-side wrong-kind reject).
- `set-phase plan my-slug --require-pipeline P --current-phase "Phase 2"` updates
  `current_phase`.
- `acquire issue 0` / `acquire issue abc` → exit 2 (propagated validation).
- `claim-work-item.sh` absent from `script-ownership.md` / `STALE_LIST` /
  `tier1-shipped-hashes.txt` (W1.9 assertion).
- `bash tests/run-all.sh` green; both new test files pass; mirror byte-equal.

### Dependencies
None (foundation phase). Depends on the existing claim-issue.sh / claim-plan.sh /
sanitize-pipeline-id.sh remaining in place.

## Phase 2 — Wire `/do`, `/quickfix`, `/investigate` onto the wrapper

### Goal
Add acquire-on-pickup / release-on-resolve fences to the three unwired
consumers, calling `claim-work-item.sh`, honoring the D5 universally-reached
release policy per consumer. Each consumer is independently verifiable. Re-anchor
all cited line ranges against the current files before editing (DA D11 — several
round-1 anchors are approximate).

### Work Items
- [ ] W2.1 — `/investigate` (`skills/investigate/SKILL.md`): in Phase 1 step 1,
  immediately after parsing `#N` (Phase 1 step 1, `SKILL.md:54`) and before reproduction,
  acquire `issue <N>`. On exit 10 (foreign): report "issue #N is being worked by
  another pipeline; declining" and stop. On exit 11: report fs-error and stop.
  Add the **single terminal release** (resolved OR abandoned) covering BOTH the
  Phase 5 success report AND the abandon paths (two-attempt-limit
  `SKILL.md:186-191`, couldn't-reproduce / abandoned report `SKILL.md:261`).
  Use `release issue <N> --require-pipeline "$PIPELINE_ID"`. Resolve `PIPELINE_ID`
  via the sanitizer (mirror `/run-plan`'s
  `${ZSKILLS_PIPELINE_ID:-investigate.$TRACKING_ID}` pattern, sanitized).
- [ ] W2.2 — `/do` (`skills/do/SKILL.md`): add an acquire step between Phase 1.5
  arg-parse (issue number + LANDING_MODE resolved) and Phase 2 dispatch
  (`SKILL.md:715-725`) — guarded on "an issue number is in scope" (the
  `--force`-override-on-`#N` path). Acquire `issue <N>`; exit 10 → decline+stop;
  exit 11 → fs-error+stop. **Release placement (corrects round-1):**
  - **Worktree/direct (Paths B/C):** release in **Phase 5 Report**
    (`SKILL.md:859`) — the universal terminal reached on BOTH `auto` and
    **non-`auto`** exits — AND on the error-handling exits (verification-fail,
    task-too-big, push-fail; `SKILL.md:909`). Do **NOT** place the release in
    Phase 4 Land (`SKILL.md:819`, gated `Only reached if AUTO_FLAG=1`) — that
    would leak on the dominant non-`auto` path (DA D2).
  - **PR mode (Path A):** release in `skills/do/modes/pr.md` post-`/land-pr`
    finalize, **release-on-resolution regardless of `created` vs `merged`** and
    on every abandon path (D5 walk-away). Do NOT copy `/fix-issues`'s
    `HOLD-on-created` arm (reviewer #7).
- [ ] W2.3 — `/quickfix` (`skills/quickfix/SKILL.md`): add acquire at WI 1.8
  (Tracking setup, `SKILL.md:640-653`, where PIPELINE_ID is established) BEFORE
  WI 1.9 branch creation (`git checkout -b`, `:730`) — guarded on the
  `#N`-via-force path. Acquire `issue <N>`; exit 10 → decline+stop; exit 11 →
  fs-error. Release in Phase 7 post-`/land-pr` finalize
  (**release-on-resolution**, D5) AND on the abandon paths (test-fail, commit-fail,
  push-fail — re-anchor; cited ranges are approximate per DA D11).
- [ ] W2.4 — Each consumer fence resolves the wrapper path:
  `"$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/claim-work-item.sh"`
  (single mirror-lane path, matching `/fix-issues` pr.md's `CLAIM_HELPER`
  precedent at `pr.md:336`; reviewer #8). Phase 2 behavioral ACs are therefore
  exercised against the installed mirror, not the source tree — the
  source-tree-testable layer is Phase 1's script behavior matrix.
- [ ] W2.5 — Bump `metadata.version` for `skills/do/SKILL.md`,
  `skills/quickfix/SKILL.md`, `skills/investigate/SKILL.md`; mirror each via
  `scripts/mirror-skill.sh <name>`.
- [ ] W2.6 — `bash tests/run-all.sh` green.

### Design & Constraints
- **Acquire call shape (D8 — single rule):**
  `bash "$WRAPPER" acquire issue "$ISSUE_NUM" --pipeline-id "$PIPELINE_ID" --sprint-id "$PIPELINE_ID"`.
  All three consumers pass `--sprint-id "$PIPELINE_ID"` (sprint_id == pipeline_id
  sentinel; dashboard cosmetic accepted per D8). No implementer choice.
- **Decline-on-foreign (exit 10):** one-shot user/cron invocations, not sprint
  loops — no "next candidate." exit 10 ⇒ STOP this invocation with a clear
  message, NOT `continue`.
- **Self-re-entry (exit 0 on re-acquire):** narrow role per D5 — covers the rare
  re-fire-before-release window; NOT a HOLD mechanism.
- **Release ownership gate + exit-12 disposition (DA D9 — distinguish):** every
  release passes `--require-pipeline "$PIPELINE_ID"`. On the **resolve/success**
  release, exit 12 is a WARN-worthy ANOMALY (someone replaced your claim
  mid-work) — log it loudly, do not silently swallow. On the **abandon /
  idempotent** path, exit 12 (or idempotent dir-absent → exit 0) is benign —
  log-and-continue. Do NOT blanket-`|| true` all release exit-12s.
- **D5 walk-away:** `/do` worktree/direct release in Phase 5 (universal
  terminal), `/do` PR-mode + `/quickfix` release on PR resolution regardless of
  `created`/`merged`. Do NOT copy `/fix-issues`'s HOLD-on-`created`.
- **Skill-file hardcode discipline:** any new fence referencing config-derived
  values sources `zskills-resolve-config.sh` per the canonical prelude.

### Acceptance Criteria
- `grep -c 'claim-work-item.sh' skills/{do,quickfix,investigate}/SKILL.md` each
  ≥ 2 (acquire + release); `grep 'claim-work-item.sh.*release'` present in each.
- With a foreign `issue-<N>` claim present, dispatching `/investigate #N` (or
  `/do --force #N`, `/quickfix #N force`) declines with the documented message
  and creates no worktree/branch.
- With a self-owned claim (same PIPELINE_ID), re-running proceeds (no spurious
  decline).
- **Non-`auto` `/do --force #N` (worktree/direct) reaches Phase 5 Report and
  releases the claim** (`.zskills/claims/issue-<N>/` gone) — the DA-D2 leak case.
- After a `/investigate` run resolves OR abandons, `.zskills/claims/issue-<N>/`
  is gone.
- After `/do`/`/quickfix` PR mode lands OR opens a PR (created), the claim is
  released.
- All three SKILL.md mirrors byte-equal; `metadata.version` bumped on each;
  `bash tests/run-all.sh` green.

### Dependencies
Phase 1 (the wrapper must exist + be mirrored before consumers can call it).

## Phase 3 — CLAUDE_TEMPLATE rule + conformance sentinels + docs

### Goal
Land the cross-cutting discipline where it propagates (CLAUDE_TEMPLATE.md),
defend the per-skill wiring against the #729 accidental-revert class via
conformance sentinels, and document the primitive. **No script-ownership.md
edits** (D1).

### Work Items
- [ ] W3.1 — Add a section to `CLAUDE_TEMPLATE.md`: "**Claim a work-item before
  working it.** Any agent about to work a tracked GitHub issue or plan MUST
  acquire its claim first and release on resolve/abandon. `/fix-issues` and
  `/run-plan` do this natively; `/do`, `/quickfix`, `/investigate` claim via the
  shared `claim-work-item.sh` wrapper. NO TTL/sweep — release is explicit.
  Foreign-held (exit 10) → decline; self-re-entry (exit 0) → proceed. Enforcement
  for the three ad-hoc consumers is advisory (prose + this rule), not a runtime
  hook." Reference the exit contract. **Use plain prose / resolved-variable
  discipline only — introduce NO `{{...}}` token lacking a substitution-map entry
  (the renderer EXITS 2 on unsubstituted placeholders; reviewer #14).**
- [ ] W3.2 — Re-render the managed rules so `.claude/rules/zskills/managed.md`
  picks up the new section: run the documented re-render path
  (`scripts/render-managed-rules.py --config .claude/zskills-config.json --out`,
  per `update-zskills/SKILL.md:997,1921`) and confirm
  `tests/test-managed-md-up-to-date.sh` passes (CLAUDE_TEMPLATE ↔ managed.md gate).
- [ ] W3.3 — Add conformance sentinels to `tests/test-skill-conformance.sh`: one
  per consumer asserting `skills/{do,quickfix,investigate}/SKILL.md` each contain
  a `claim-work-item.sh ... acquire` invocation AND a `claim-work-item.sh ...
  release` invocation (the #729 accidental-revert defense — text-presence only,
  per D6's explicit advisory-not-mechanical scope). **Precedent (round-2
  reviewer NIT-2):** the two-pass-grep pattern this borrows lives in the
  *dedicated* claim-conformance files — `test-fix-issues-claim-conformance.sh:118-124`
  (≥2 CLAIM_HELPER + ≥2 acquire) and `test-plan-claim-conformance.sh` — NOT in
  `test-skill-conformance.sh` (which has 0 claim refs today). The pattern
  transfers cleanly (`test-skill-conformance.sh` already has a `check_fixed()`
  helper at `:56` for grep-presence assertions); placing the new sentinels in
  `test-skill-conformance.sh` is fine, but name the precedent location
  accurately.
- [ ] W3.4 — Document the wrapper's CLI + exit contract. **Resolved target
  (corrects round-1 hedge, reviewer #10):** there is no `/claim-work-item` skill
  (D1), so NO `docs/skills/` page. Add a concise "claim-work-item.sh — CLI + exit
  contract" reference section to **`skills/create-worktree/SKILL.md`** (the owner
  skill body) under a "Scripts" / "Owned scripts" heading; if create-worktree has
  a `references/` dir, place a `references/claim-work-item.md` and link it from
  SKILL.md instead. Do NOT edit `docs/skills/README.md` (verified this round: it
  indexes skills, not scripts — confirm before skipping). The SKILL.md edit
  requires a `metadata.version` bump (already done in W1.6 for the script; if this
  is a separate later edit, bump again and re-mirror).
- [ ] W3.5 — **(REMOVED — corrects round-1.)** No `script-ownership.md` row/count
  to re-verify (D1). Instead re-verify W1.9's absence assertions still hold after
  all edits.
- [ ] W3.6 — `bash tests/run-all.sh` green (must include the managed-md gate, the
  new conformance sentinels, and W1.9's registry-absence assertions).

### Design & Constraints
- **Rule home (D6):** CLAUDE_TEMPLATE.md is the propagating surface
  (auto-rendered into consumers' `.claude/rules/zskills/managed.md`). NOT a memory
  anchor. The rule is cross-cutting → CLAUDE_TEMPLATE's charter.
- **Renderer placeholder gate (reviewer #14):** the renderer exits 2 if rendered
  output contains unsubstituted `{{...}}`. New prose must not introduce such a
  token.
- **Conformance sentinel scope (#729 + D6):** text-presence only — the assertion
  defends the wiring text against silent revert (e.g. stale-copy merge
  overwrite); it does NOT and cannot assert runtime acquire. Grep the literal
  `claim-work-item.sh` + `acquire`/`release` per consumer SKILL.md.
- **No new skill / no docs/skills page / no script-ownership row** (D1).
- **Skill-file hardcode discipline:** CLAUDE_TEMPLATE prose / managed.md is
  governed by the same hardcode deny-list where it contains fenced bash — use
  resolved variables for any config-derived literal.

### Acceptance Criteria
- `CLAUDE_TEMPLATE.md` contains the claim-before-work rule;
  `.claude/rules/zskills/managed.md` contains the rendered equivalent;
  `tests/test-managed-md-up-to-date.sh` passes.
- `tests/test-skill-conformance.sh` has new per-consumer sentinels; removing a
  consumer's acquire/release wiring text makes the suite fail (spot-verify by
  reasoning, NOT by actually breaking main).
- `skills/create-worktree/SKILL.md` (or its referenced `references/` file)
  documents the wrapper CLI + exit contract; `metadata.version` bumped + mirrored.
- `claim-work-item.sh` remains absent from `script-ownership.md` / `STALE_LIST` /
  `tier1-shipped-hashes.txt`.
- `bash tests/run-all.sh` green.

### Dependencies
Phase 2 (the consumer wiring must exist for the sentinels to assert against and
for the CLAUDE_TEMPLATE rule to describe accurately).

## Out of scope (explicit)

- **Migrating `/fix-issues` or `/run-plan` onto the wrapper** (D7). They keep
  calling claim-issue.sh / claim-plan.sh directly; their conformance tripwires
  (`test-fix-issues-claim-conformance.sh:118-124`, plan-claim battery) stay green
  untouched. `/run-plan` already satisfies #803's acceptance natively (it
  claims at `SKILL.md:587-602` and releases at its terminals), so this is not a
  deferred requirement.
- **A new / broadened PreToolUse hook** gating `/do`/`/quickfix`/`/investigate`
  (D6). Enforcement for the three new consumers is prose + CLAUDE_TEMPLATE +
  text-presence conformance sentinel — **advisory, not mechanical**. A broadened
  hook (at least for `/do`'s `do/<slug>` worktree) is a named follow-up.
- **`/run-plan:597` same-pipeline re-acquire conflation fix** (D7) — a SEPARATE
  latent bug from #803's acceptance (which `/run-plan` already meets). On a
  chunked `finish auto` run, the phase-N+1 fire re-reaches the acquire fence
  (`SKILL.md:587-602`) and self-declines at `:597` because the fence has no
  same-pipeline skip guard. Fixing it (a skip guard at the fence, or migrating
  `/run-plan` onto the wrapper's self-re-entry) is a named follow-up, NOT
  "benign/unreachable."
- **A unified single claim.json schema or merged claim-resource.sh** (D2). The
  wrapper dispatches; storage stays kind-specific.
- **Any TTL / heartbeat / sweep / refresh** (D4).
- **TOCTOU spurious-decline elimination** (D3) — the absent-claim.json → exit 10
  race is accepted (conservative decline; never steal).
- **Dashboard "synthetic sprint" display tweak for the synthesized `sprint_id`**
  (D8) — the synthesized value is emitted into the issues JSON but has no current
  `app.js` chip consumer; any future display handling is out of scope.
- **Dashboard collector changes** — dirs/regexes/schemas unchanged (D2), so
  `collect.py` needs no edit.
- **A `list` subcommand on the wrapper** (reviewer #6) — no consumer needs it;
  callers use the delegates' `list` directly.

## Plan Quality

**Drafting process:** /draft-plan with 2 rounds of adversarial review (reviewer + devil's-advocate + refiner)
**Convergence:** Converged at round 2 (round-1: 26 findings all addressed; round-2: structural fixes held, only editorial corrections remained)
**Remaining concerns:** All genuinely-open items are explicitly out-of-scope with rationale and named as follow-ups:
- Full migration of `/fix-issues` + `/run-plan` onto the wrapper (D7) — both already claim+release correctly; migration would break their conformance batteries for no #803 gain.
- The `/run-plan:597` same-pipeline re-acquire latent bug (D7) — a chunked `finish auto` phase-N+1 fire re-reaches the acquire fence (`SKILL.md:587-602`) and self-declines because the fence has no same-pipeline skip guard. SEPARATE from #803's acceptance (which `/run-plan` already meets); fix via a fence skip-guard or wrapper migration is a named follow-up.
- A runtime PreToolUse hook for the three non-`/fix-issues` consumers (D6) — enforcement is advisory (prose + CLAUDE_TEMPLATE + text-presence sentinel); a broadened hook (at least for `/do`'s worktree) is a named follow-up.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 14 (1 BLOCKER/3 MAJOR/6 MINOR/4 NIT) | 12 (2 CRITICAL/4 HIGH/4 MEDIUM/2 LOW) | 26/26 (24 fixed, 2 justified NITs) |
| 2     | 4 (NIT only) | 5 (1 MEDIUM/2 LOW/2 NIT) | editorial corrections applied; converged |
