---
issue: 310
title: /quickfix argument-grammar inconsistency + cross-skill auto semantics drift
created: 2026-05-16
status: active
---

# Plan: /quickfix argument-grammar redesign + cross-skill `auto`/`unattended` alignment

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

Issue [#310](https://github.com/zeveck/zskills-dev/issues/310) reports two coupled problems:

1. **Grammar inconsistency.** `/quickfix` uses a mixed grammar (positional `auto`, plus six `--` flags: `--branch`, `--yes`/`-y`, `--from-here`, `--skip-tests`, `--force`, `--rounds N`). Sibling PR-landing callers (`/run-plan`, `/fix-issues`, `/do`) use positional-only tokens for boolean modes. The divergence has no design rationale in the prose; `--yes` is vestigial (only `tests/test-quickfix.sh` Case 43 at line ~1129 invokes it — a test scaffold, not a real workflow).
2. **`auto` semantic drift.** Three tiers of `auto` exist today across the 4 PR-landing callers — narrow (`/quickfix`, and `/do` post-PR-#303), medium (`/run-plan`: the chunked-cron between-phase fire mechanism when in `finish` mode + auto-merge), and broad (`/fix-issues`: Phase 2 issue-list approval bypass + `plan auto` selection bypass + autonomous cherry-pick + auto-merge). The same token means different things. Users who learn `auto` in one skill are surprised in another, and the "broad" tier conflicts with WI 1.5.5's load-bearing scope-confirmation protection and with the PR #309 serial-loop rule.

**This plan does these things:**

- **Grammar redesign for `/quickfix`** (Q1): drop vestigial `--yes`/`-y`; make boolean flags positional (`from-here`, `skip-tests`, `force`); keep value-taking flags as `--` (`--branch <name>`, `--rounds N`). Matches sibling convention for booleans, principled for value-takers.
- **Cross-skill `auto`/`unattended` split** (Q2): the canonical meaning of `auto` is narrowed to *auto-merge pass-through to `/land-pr`*. A new positional token `unattended` carries the "skip approval gates" semantic each skill currently bundles into broad-`auto`. The two are orthogonal. **`/run-plan`'s `auto` is special-cased** (see D2-RP below): the existing `finish auto` composite (chunked-cron) is preserved by re-keying the between-phase-fire mechanism to `unattended` while leaving the `finish-auto` composite token alive as a backward-compatible alias.
- **WI 1.5.5 context-aware skip + `/quickfix unattended` semantics** (Q3): preserve the load-bearing protection for the ambiguous case (multi-file dirty tree, vague description) while removing friction for the unambiguous case. `unattended` in `/quickfix` (D3-QF, revised) routes through the WI 1.5.5a detector to force the SKIP branch — the token does something observable instead of being vestigial.
- **Hard-break migration with cron-context survival** (Q4): old flags / old broad-`auto` semantics emit a redirect error pointing at the new grammar. Per `feedback_no_premature_backcompat.md`, zskills has no external consumers; deprecation periods carry cost without benefit. **Exception: cron-fired contexts.** Because cron-fired sessions have no human to read a stderr WARN, the migration includes a runtime auto-promote (D5, revised). Note: round-1 also proposed a CronList scan script at landing-day; round-2 reviewer H2 surfaced that `CronList`/`CronDelete`/`CronCreate` are model-layer MCP tools (no bash CLI), so the "script" form is structurally impossible. WI 7.3 is reframed as **skill-prose runbook in /update-zskills** that instructs the model to perform the migration on user confirmation, with the runtime auto-promote serving as the safety net for users who never re-run /update-zskills.

### Locked decisions (set before draft, refiner may push back)

- **D1 — Grammar for `/quickfix`:** drop `--yes`/`-y` entirely (vestigial, only test Case 43 uses it; rewrite Case 43). Convert `--from-here`/`--skip-tests`/`--force` to positional tokens `from-here`/`skip-tests`/`force` (case-insensitive). Keep `--branch <name>` and `--rounds N` as `--` flags. Keep `auto` positional (no change). Rationale for keeping `--branch`/`--rounds` as `--` flags: they take values, and `every SCHEDULE`-style positional-with-value (the in-repo precedent in `/run-plan`/`/fix-issues`) is appropriate for slot-defined value-takers like time expressions, but less appropriate for free-form values like branch names that could otherwise collide with other positional tokens (e.g. a branch literally named `force`). Acknowledged compromise: future work may unify; not in scope here. (Address Reviewer M5.)
- **D2 — `auto` semantics across skills (narrowed, with per-skill nuance).**
  - **`/quickfix`:** `AUTO_FLAG=1` → pass `--auto` to `/land-pr`. Already exists; no change.
  - **`/do`:** Per PR #303 (which absorbs `/do auto` recognition; `AUTO_FLAG` is set in /do's pre-flight regex block and consumed in `modes/pr.md`). This plan rebases over #303 — see D6.
  - **`/run-plan` (D2-RP, special case — REVISED per Reviewer M2):** Today `auto` in `/run-plan` has TWO related uses, both load-bearing:
    - (a) **Standalone `auto`** (per `skills/run-plan/SKILL.md:50` argument doc + prose at lines 38–40, 906–908): "bypass approval gates, auto-land to main via cherry-pick." This is the "autonomous between-phase advance" semantic.
    - (b) **`finish auto` composite** (line ~122 FINISH_MODE detection): parses to `FINISH_MODE="finish-auto"`, the chunked-cron between-phase fire mechanism.
    The narrowing decision for `/run-plan`: the `auto` token henceforth means ONLY "pass `--auto` to per-phase `/land-pr` dispatches" (narrow auto-merge). The "autonomous between-phase advance" semantic in (a) moves to `unattended`. The `finish-auto` composite alias is preserved as a backward-compatible alias: `finish auto` parses to `FINISH_MODE="finish-auto"` AND sets `UNATTENDED_FLAG=1` AND sets `AUTO_FLAG=1`. This preserves the load-bearing user workflow (`/run-plan plan.md finish auto every 4h`) AND covers (a) via the runtime cron-context auto-promote (WI 3.3) during the 3-month migration window. After `MIGRATION_END_DATE`, standalone `auto` without `unattended` no longer implies autonomous advance; users must type `auto unattended` explicitly.
  - **`/fix-issues`:** Today `auto` is detected by inline regex (`[[ "$ARGUMENTS" =~ ... [aA][uU][tT][oO] ... ]]`) and consumed at the **model layer** in prose at lines 1080, 1082, 1509, 1530 (and Phase 2 select-all sites at 591–603). There is no `AUTO_FLAG` bash variable. This plan adds one (a real bash parser arm, parallel to the new `UNATTENDED_FLAG`), and Phase 3 explicitly **rewrites the model-layer prose** at each enumerated site to read the new variable names. New narrow `auto` = "pass `--auto` to per-issue `/land-pr` dispatches" (the model-layer prose at 1509–1530 already covers this path; Phase 3 confirms and narrows).
- **D3-QF — `unattended` in `/quickfix` (REVISED from round 1 to address DA H5):** `unattended` forces the WI 1.5.5a "skip" branch. Concretely: when `UNATTENDED_FLAG=1`, the model treats `SCOPE_AMBIGUOUS=0` regardless of dirty-tree shape, skips the WI 1.5.5 confirmation, and emits a stderr NOTE: `NOTE: WI 1.5.5 scope-confirmation skipped (unattended).`. This means the token does something observable in `/quickfix`. The user accepts the risk: `unattended` is an explicit "I trust the model to scope correctly" opt-in. The detector logic from WI 5.1 still applies in NON-unattended mode (the conservative skip-when-unambiguous behavior preserves protection for users not opting in).
- **D3 — `unattended` token (other 3 skills):** positional, case-insensitive, recognized anywhere in the arg vector. Each skill defines what gates `unattended` bypasses for ITS workflow (per-skill table in WI 1.1, prose enumeration in Phase 2). Composes with `auto` (they're orthogonal). Convenience alias rule: typing `unattended` alone (without `auto`) does NOT imply `auto` — keeps tokens orthogonal and reduces "I didn't ask to auto-merge" surprise. Users wanting both type both. **Anti-pattern callout in reference doc:** `/fix-issues 5 unattended` (without `auto`) leaves PRs at `pr-ready`. To run fully autonomously, use `/fix-issues 5 auto unattended`. (Address Reviewer M4.)
- **D4 — WI 1.5.5 scope-detector (unchanged) + tightened substring match:** WI 1.5.5 fires when `$DIRTY_FILES` has 2+ entries OR when `$DESCRIPTION` does not literally name the single dirty file. Skips when exactly one dirty file AND its basename appears as a **word-boundary substring** of `$DESCRIPTION`. (Tightened from raw substring to word-boundary to address Reviewer M7 / DA M8: "fix foobar" must NOT match dirty file `foo.md`. Word-boundary = preceded and followed by whitespace, punctuation, or string boundary. Hyphen-space normalization: also try matching basename with hyphens converted to spaces against description, to handle `the-build.sh` ↔ "the build".)
- **D5 — Migration (REVISED to address Reviewer H8 / DA H3 round-1, then Reviewer H2/H3 + DA H1/H3 round-2):** hard-break for the 7 removed/changed flags in `/quickfix` (each errors with exit 1 + redirect message). For cross-skill `auto` narrowing in `/run-plan` and `/fix-issues`, the plan implements **TWO migration layers**:
  - **Layer 1 — Runtime auto-promote (the safety net).** At parser entry, when `AUTO_FLAG=1 && UNATTENDED_FLAG=0 && FINISH_MODE != "finish-auto"` AND today's date < `MIGRATION_END_DATE`, the parser **unconditionally promotes** `UNATTENDED_FLAG=1` and emits a one-line stderr NOTE. Round-1 attempted to scope this to "cron-fire context only" via a `cron-fire-detected` predicate, but round-2 (Reviewer H2/DA H3) verified no such predicate exists in /run-plan today and that inventing one (distinguishing cron-fired `now` from interactive `/run-plan ... now`) is design-non-trivial. **Decision: drop the cron-vs-interactive distinction.** Always promote during the migration window. The cost is one extra stderr NOTE on interactive `auto` invocations during 3 months; the benefit is correctness (no cron-hang) and a 3-line implementation. Set `MIGRATION_END_DATE` at IMPLEMENTATION time, not at draft time (see WI 3.3 for the exact rule per Reviewer M5).
  - **Layer 2 — Skill-prose CronList migration runbook in /update-zskills (NOT a bash script).** Round-1 specified a `scripts/migrate-auto-unattended-crons.sh`, but `CronList`/`CronDelete`/`CronCreate` are model-layer MCP tools (verified: 0 hits in `scripts/`; only `skills/` prose references). A bash script cannot invoke them. **Revised approach (Reviewer H2 Option A):** add a model-layer runbook section to `/update-zskills` skill prose instructing the model to (a) call `CronList`, (b) match prompts against `Run /(run-plan|fix-issues) ... auto ...` without `unattended` and without `finish auto`, (c) present a diff to the user, (d) on confirmation, call `CronDelete` + `CronCreate` with the rewritten prompt. The runbook runs when the user invokes `/update-zskills` and is a one-shot pointer (no-op after migration since post-migration crons have `unattended`).
  - Existing user workflows (`/run-plan plan.md finish auto every 4h`) survive via D2-RP's `finish-auto` composite alias even without these layers; Layer 1 covers non-composite cron prompts (e.g. `/fix-issues 5 auto every 4h`) AND newly-scheduled `every`-mode crons (whose generated prompts must also include `unattended` going forward — see WI 3.2 round-2 expansion).
- **D6 — PR #303 coordination (REVISED to address Reviewer M3 / DA H2):** PR #303 adds `/do auto` recognition (verified via `gh pr diff 303` 2026-05-16: introduces `AUTO_FLAG` pre-flight regex block + argument-hint update + `modes/pr.md` wiring). This plan SUPERSEDES #303 for the `auto` semantic but BUILDS ON its `AUTO_FLAG` wiring. **Phase 1 closes #303** with a redirect comment to this plan's PR (decision made at Phase 1, not deferred to Phase 6 — Reviewer M3 mitigation). **Phase 2 cherry-picks the AUTO_FLAG-introducing edits from #303 into this plan's feature branch at the start of WI 2.4 work**, then adds `UNATTENDED_FLAG` symmetric to it. This avoids a stale-fork situation: PR #303's diff is small and well-bounded (5 hunks; verified).
- **D7 — Issue #293 (Approach B native multi-mode):** out of scope. Note in Phase 1's reference doc that Approach B is an independent track; this plan's grammar cleanup makes Approach B easier to land later (positional booleans compose cleanly with mode tokens). Approach B does not block any phase here.
- **D8 — PR #309 serial-loop rule (REVISED per DA H4 round-2):** preserved. `unattended` in `/fix-issues` bypasses Phase 2 issue-list approval gate + per-issue selection gate ONLY. The for-loop iteration is structural (single-`/land-pr` dispatches, per-iter `requires.X.<id>` markers) and unchanged. **`gh issue close` correction:** round-1 D8 said the close decision "stays on AUTO_FLAG" — round-2 verification (`sed -n '530,545p' skills/fix-issues/SKILL.md`) confirms the close is actually inside `case "${LP[STATUS]:-}" in merged) ... gh issue close ... ;; *) Skipping ... ;; esac`, NOT keyed on AUTO_FLAG. The existing LP[STATUS]-keyed gate is correct (matches `feedback_automerge_blocked_means_act.md`: only close on confirmed `merged`, not on `created`/`monitored`/`auto-merge-pending`). This plan does NOT add an AUTO_FLAG gate to `gh issue close` — the existing LP[STATUS] gate is preserved unchanged. Phase 2 WI 2.3 enumerates each site explicitly. (Address DA M6 round-1 + DA H4 round-2.)
- **D9 — `/land-pr` argument vector unchanged.** `--auto` still means "request auto-merge." Nothing in this plan extends `/land-pr`.
- **D10 — Mirror + version discipline.** Every touched skill bumps `metadata.version` via `bash scripts/frontmatter-set.sh skills/<name>/SKILL.md metadata.version "$today+$hash"` and mirrors via `bash scripts/mirror-skill.sh <name>`. Skills touched: `/quickfix`, `/run-plan`, `/fix-issues`, `/do`. (4 bumps + 4 mirror runs per landing.) The `tests/test-skill-conformance.sh` byte-identity assertion (cross-cutting; see Phase 7 WI 7.1 for the actual grep recipe) covers all mirrors. (Address Reviewer L4.)
- **D11 — Cross-cutting argument-hint length budget (NEW):** Verify each touched skill's argument-hint against any cap. Round-1 verified no formal cap in `references/skill-description-budget.md` as of 2026-05-16; per Reviewer L4 round-2, **implementer re-greps this file at Phase 6 time** to confirm no formal cap was added in the interim (e.g. via `grep -iE 'argument-hint|character|cap|length' references/skill-description-budget.md`). If a cap exists, honor it; otherwise apply the soft ≤150 guideline. Post-plan lengths estimated: `/quickfix` ≈ 99 chars; `/fix-issues` ≈ 78 chars; `/run-plan` ≈ 80 chars; `/do` ≈ 135–141 chars (with [unattended] added to #303's already-updated hint). The /do length is the highest — Phase 6 verifies and, if a cap exists, compacts. (Address Reviewer L1, DA M9, Reviewer L4 round-2.)

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Decisions reference doc + CLAUDE_TEMPLATE prose + PR #303 close | 🟡 | `d02b8a8` | Locks D1–D11 into `references/auto-unattended-semantics.md`; #303 was already MERGED at draft-time so close was substituted with redirect comment (AC1.3/1.4 reformulated; see drift tokens) |
| 2 — Real `AUTO_FLAG` + `UNATTENDED_FLAG` parser arms in all 4 skills | 🟡 | `4cfe0ad` | 4 skills + 4 mirrors + 17 conformance assertions; tests 3194/3194; #303 cherry-pick was no-op (already in main); 2 drift tokens: do-arg-hint 141→146 (3.5%), hash-script-arg-shape bug in plan loop |
| 3 — Model-layer prose rewrite for narrow `auto` + `unattended` gating | 🟡 | `c352fab` | 5 /run-plan + 3 /fix-issues prose sites rewritten; 2 migration auto-promotes (MIGRATION_END_DATE=2026-08-17); cron-prompt regen incl. `unattended`; $AUTO bound from $AUTO_FLAG in modes/pr.md (was orphaned); tests 3202/3202; line-number drift in plan tables (Phase 2 shift) → /refine-plan post-Phase-7 |
| 4 — `/quickfix` grammar rework (drop `--yes`, positional booleans) | 🟡 | `e8bb801` | Parser: migration redirects FIRST (lines 108-117) → positional case-arms (130-146); YES_FLAG + `read -r` confirmation block deleted entirely; arg-hint=99 chars; Cases 49+57 deleted, 43 rewritten, 60-69 added for migration+positional+greedy-fallthrough coverage; tests 3217/3217 (+15) |
| 5 — `/quickfix` WI 1.5.5 context-aware logic + `unattended` skip | 🟡 | `7e231e6` | WI 1.5.5a detector inserted (UNATTENDED_FLAG=1 → SKIP unconditionally; ≥2 dirty files OR no word-boundary match → AMBIGUOUS); parser-exit `FLAGS:` stderr echo so model reads flags from turn context; rationale paragraph appended; 4 new tests (70-73); tests 3221/3221 |
| 6 — `/do` `unattended` parity (rebases on #303's `auto` work) | 🟡 | `5917200` | Forward-placeholder semantic documented in /do + reference doc (no current /do gate to bypass); regex-arm conformance assertion (matches /do's `[[ =~ ]]` form, not the `case` form other 3 callers use); Case 17 4-arm smoke (unattended/no/UPPER/auto+un); arg-hint 146 chars (< soft 150 cap, no formal cap); tests 3223/3223 |
| 7 — Conformance + integration tests + cron migration + docs sweep | ⬚ | | Grep-recipe-based conformance assertions (not line refs); model-layer cron-migration runbook in /update-zskills (NOT a bash script per round-2 H2 — CronList is MCP) |

## Phase 1 — Decisions reference doc + CLAUDE_TEMPLATE prose + PR #303 close

### Goal

Lock in D1–D11 in a single canonical reference document so subsequent phase agents (and downstream consumers' agents) cite one source for `auto` vs `unattended` semantics. **Close PR #303** with a redirect comment so Phase 6 is not coupled to its merge state. No skill behavior changes in this phase — pure spec + coordination.

### Work Items

- [ ] **WI 1.1 — Create `references/auto-unattended-semantics.md`** at the repo root under `references/` (sibling to `references/skill-versioning.md`). Placement rationale: top-level `references/` is the established home for cross-cutting infrastructure docs (versioning, hooks); per-token semantics for the 4 PR-landing callers is cross-cutting at the same level. (Address DA M2.)

  Contents:
  - One-paragraph rationale: the two concerns (auto-merge vs human-review-gate) are orthogonal and historically conflated under `auto`; this redesign separates them.
  - Definition table:

    | Token | Meaning (canonical) | Caller behaviors |
    |-------|---------------------|------------------|
    | `auto` | Pass `--auto` to `/land-pr` on the resulting PR(s). Nothing else. | `/quickfix`: PR opens with auto-merge requested. `/do` (per #303): same, in PR mode only. `/run-plan`: each per-phase `/land-pr` dispatch passes `--auto`. `/fix-issues`: each per-issue `/land-pr` dispatch passes `--auto`. **Note for /run-plan:** the legacy `finish auto` composite (chunked-cron) is preserved as a backward-compatible alias that sets BOTH `AUTO_FLAG=1` AND `UNATTENDED_FLAG=1`. |
    | `unattended` | Skip human-review-gate checkpoints inside the skill. | `/quickfix`: force WI 1.5.5a SKIP branch (model bypasses scope confirmation; stderr NOTE emitted). `/do`: skip the "ready to land?" confirmation between implementer and landing IF such a gate exists; otherwise documented forward-placeholder. `/run-plan`: skip between-phase "continue?" prompts (replaces what `finish auto` used to mean for run-plan chunked execution; cron-fired phases continue automatically). `/fix-issues`: skip Phase 2 issue-list approval gate + per-issue selection gate. |
  - Composition rules:
    - `auto` and `unattended` are independent. Typing one does not imply the other.
    - Order-insensitive: `/fix-issues 5 auto unattended` ≡ `/fix-issues 5 unattended auto`.
    - Case-insensitive (matches existing `auto` parsing).
    - `/run-plan finish auto` composite: parses as `FINISH_MODE="finish-auto"` AND `AUTO_FLAG=1` AND `UNATTENDED_FLAG=1` — the load-bearing backward-compatible alias.
  - **Anti-pattern callout (mandatory, prominent, first example after table):**
    > **`unattended` alone is NOT full autonomy.** `/fix-issues 5 unattended` skips approval gates but does NOT auto-merge. PRs sit at `pr-ready` waiting for manual merge. For fully unattended sprints, use `/fix-issues 5 auto unattended`.
  - Explicit non-rules:
    - `unattended` does NOT change the `/fix-issues` for-loop into parallel dispatch (PR #309 serial-loop rule).
    - `unattended` does NOT bypass branch-collision check, test-cmd alignment gate, parallel-invocation gate, or any safety guard.
    - In `/quickfix`, `unattended` forces the WI 1.5.5a SKIP — explicit risk acceptance.
  - Migration note: existing `/fix-issues N auto` invocations that previously triggered broad-auto now trigger ONLY auto-merge. Users wanting prior behavior: `/fix-issues N auto unattended`. **Cron migration:** see D5; landing-day CronList scan + 3-month runtime promote period.
  - Cross-references: link to `feedback_auto_arg_is_auto_merge.md`, link back to this plan.

- [ ] **WI 1.2 — Add CLAUDE_TEMPLATE.md prose** under a new section `## auto and unattended tokens` (placed at top-level alongside existing convention sections, NOT under `## Git Rules` — address DA L1). One short paragraph + the anti-pattern callout + a pointer to `references/auto-unattended-semantics.md`. Budget: ≤15 lines (relaxed from ≤8 to fit the anti-pattern callout — address DA M7). The full per-skill table stays in the reference doc; CLAUDE_TEMPLATE just has the headline rule + anti-pattern + link.

- [ ] **WI 1.3 — Close PR #303** with a comment redirecting to this plan's PR (PR # known after Phase 2 lands; agent updates the comment then): `Closing in favor of issue #310's broader cross-skill auto/unattended redesign (see PR <NN>). The AUTO_FLAG wiring introduced here is preserved and extended.` Use `gh pr close 303 --comment "..."`. This removes the Phase 6 coordination burden.

- [ ] **WI 1.4 — Cherry-pick PR #303's `AUTO_FLAG` wiring into this plan's worktree** as a single commit at end of Phase 1. Files touched by #303 (verified `gh pr diff 303 --name-only` 2026-05-16, round-2 corrected count): **5 files** — `skills/do/SKILL.md`, `skills/do/modes/pr.md`, `tests/test-do.sh`, AND the mirrors `.claude/skills/do/SKILL.md`, `.claude/skills/do/modes/pr.md`. Round-1 plan undercounted (Reviewer M1 round-2).
  - Use `git cherry-pick <303-head-commit>` (single commit). The cherry-pick touches both source AND mirror; that's fine — Phase 2 WI 2.5 will re-mirror anyway, so a no-op mirror diff is expected (and any stale mirror gets corrected).
  - **Conflict handling (DA M6 round-2):** if cherry-pick conflicts are non-trivial (>2 hunks needing manual resolution), STOP and report back to orchestrator. Do not force the merge. Recovery: rebase #303 onto current main first via `gh pr checkout 303; git rebase main; git push --force-with-lease` (separate effort), then re-cherry-pick.
  - **Anticipated overlap with Phase 2 WI 2.4:** #303 adds `[auto]` to /do's `argument-hint`; Phase 2 adds `[unattended]` to the same hint. These are sequential edits on the same line — no conflict (Phase 2's edit happens after Phase 1's cherry-pick on the feature branch).
  - **Skill-version stage-check anticipated fire (Reviewer L2 round-2):** #303's version-bump date may be stale (it was set on #303's creation date). When cherry-picked, `block-stale-skill-version.sh` may fire on the cherry-pick commit. If so, bump /do's `metadata.version` per the hook's STOP message before re-issuing the commit. This is expected, not a failure. Rationale: this gives Phase 6 a clean starting point and avoids the "rebase or no-op" ambiguity DA H2 round-1 flagged.

### Design & Constraints

- Reference doc is the SINGLE source of truth — every subsequent phase's SKILL.md prose changes will link here, not re-state the table.
- No bash, no behavior change (except the cherry-picked #303 wiring, which is a structural pre-positioning, not new behavior in this plan).
- File path: `references/auto-unattended-semantics.md` (NOT under `skills/<name>/references/` — this is cross-skill).
- CLAUDE_TEMPLATE prose ≤15 lines (was ≤8 in round-1 draft; relaxed for anti-pattern callout per DA M7).

### Acceptance Criteria

- AC1.1 — `references/auto-unattended-semantics.md` exists with the definition table, composition rules (including `finish-auto` alias), explicit non-rules, anti-pattern callout, and migration note. (File presence + heading grep.)
- AC1.2 — `CLAUDE_TEMPLATE.md` contains an "auto and unattended tokens" section ≤ 15 lines that includes the anti-pattern callout and points to the reference doc. (grep for section heading + line count check + grep for `unattended is NOT full autonomy` literal phrase.)
- AC1.3 — PR #303 is closed (`gh pr view 303 --json state -q .state` returns `CLOSED`). Comment includes redirect link.
- AC1.4 — `git log --oneline main..HEAD` shows the cherry-picked #303 commit (single commit). `grep -n "AUTO_FLAG" skills/do/SKILL.md` returns hits matching #303's pre-flight regex block.
- AC1.5 — The reference doc's table lists exactly 4 skills (`/quickfix`, `/run-plan`, `/fix-issues`, `/do`) and exactly 2 tokens (`auto`, `unattended`). All 8 intersection cells are non-empty and describe per-skill behavior. (grep-checkable per Reviewer L2.)
- AC1.6 — No SKILL.md prose modified in this phase EXCEPT the cherry-picked #303 wiring. No `metadata.version` bumps required for the doc files themselves; #303's bump is preserved as-is.

### Dependencies

- None. First phase.

### Tests

- Manual: verifier reads `references/auto-unattended-semantics.md` end-to-end, confirms the table covers all 4 skills, and confirms composition rules are unambiguous. Verifier confirms #303 is closed and the cherry-pick landed cleanly. No automated test in this phase (pure prose + structural setup); test fixtures appear in Phase 2+.

## Phase 2 — Real `AUTO_FLAG` + `UNATTENDED_FLAG` parser arms in all 4 skills

### Goal

Establish `AUTO_FLAG` and `UNATTENDED_FLAG` as REAL bash variables, set by an explicit parser arm, in all 4 PR-landing callers. **Per Reviewer H1 / DA H1, this is a behavioral change in `/run-plan` and `/fix-issues`** — those skills today have NO `AUTO_FLAG` bash variable. They use inline `if [[ "$ARGUMENTS" =~ ... [aA][uU][tT][oO] ... ]]` checks AND model-layer prose. Phase 2 introduces the variables; Phase 3 rewrites the model-layer prose to read them. Atomicity here means: by Phase 2 end, all 4 skills have BOTH variables set by their parser. Multiple commits within Phase 2's PR-feature-branch state are fine (per Reviewer H3 mitigation — atomicity is the phase boundary, not a single commit).

### Work Items

- [ ] **WI 2.1 — `/quickfix` parser (smallest change)** (`skills/quickfix/SKILL.md`, parser block at lines 66–121).
  - `AUTO_FLAG` already exists (line 74). No change.
  - Add `UNATTENDED_FLAG=0` initializer next to `AUTO_FLAG=0` at line ~74.
  - Add a case arm next to the existing `[aA][uU][tT][oO]) AUTO_FLAG=1 ;;` at line 92:
    ```bash
    [uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]) UNATTENDED_FLAG=1 ;;
    ```
  - Update `argument-hint` (line 3) to add `[unattended]`. New shape locked in Phase 4 (WI 4.3); Phase 2 just adds the token.
  - **Carve-out for `unattended` as description prose (address DA H6):** if `unattended` is the ONLY non-whitespace token in `$ARGUMENTS` (i.e. no description, no other flags), the existing "description required" error path fires. If `unattended` appears among other description words, the case arm matches the token only when it stands alone as a word (bash `case` with `[uU][nN][aA]...` does NOT match suffixes — verified: `case "unattended-mode" in [uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]) ... ;; *) ... ;; esac` falls to `*)`, but `case "unattended"` matches). For the description-word-collision case (`/quickfix "fix the unattended bug"`), the token gets consumed by the case arm and the description becomes "fix the bug" — document this as known limitation. Users wanting `unattended` literally in the description must phrase differently or accept the lost token (this is consistent with the existing `auto` token's behavior).
  - Add prose at the parser-options listing: `**unattended** (optional) — skip the WI 1.5.5 scope-confirmation prompt. Forces the WI 1.5.5a SKIP branch unconditionally; the model bypasses scope confirmation (per D3-QF). See references/auto-unattended-semantics.md.`

- [ ] **WI 2.2 — `/run-plan` parser** (`skills/run-plan/SKILL.md`, FINISH_MODE block at lines 117–127).
  - **First**: introduce `AUTO_FLAG` as a real variable. After the existing FINISH_MODE detection at line 127, add:
    ```bash
    # AUTO_FLAG: set by standalone `auto` (regardless of finish), OR by the
    # `finish auto` composite (backward-compatible alias per D2-RP).
    AUTO_FLAG=0
    if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
      AUTO_FLAG=1
    fi
    ```
  - **Then**: introduce `UNATTENDED_FLAG`:
    ```bash
    UNATTENDED_FLAG=0
    if [[ "$ARGUMENTS" =~ (^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]($|[[:space:]]) ]]; then
      UNATTENDED_FLAG=1
    fi
    # Backward-compatible composite: `finish auto` implies BOTH flags.
    if [ "$FINISH_MODE" = "finish-auto" ]; then
      AUTO_FLAG=1
      UNATTENDED_FLAG=1
    fi
    ```
  - Note: `finish-auto` composite is set BEFORE the auto/unattended individual checks; the post-detection block at the bottom hoists both flags. This is the load-bearing user-workflow preservation.
  - Update `argument-hint` (line 4) to add `[unattended]`. Add `unattended` bullet to the args listing (line ~76 area), after the existing `auto` bullet.
  - **Token stripping (DA M4 round-2):** locate the existing `$ARGUMENTS` strip logic via `grep -nE 'sed -E.*\[aA\]|sed.*strip|ARGUMENTS=' skills/run-plan/SKILL.md`. Extend the strip chain to also remove the `unattended` token before downstream consumers (cron-prompt construction, focus parsing). Pattern: `sed -E 's/(^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]([[:space:]]|$)/\1\2/g'`. Use the pattern from `skills/do/SKILL.md` post-#303 cherry-pick (line ~663 area) as reference if present.

- [ ] **WI 2.3 — `/fix-issues` parser** (`skills/fix-issues/SKILL.md`, argument-listing area at lines 76–82). Today there is NO bash `AUTO_FLAG` — all `auto` decisions are at the model layer. Introduce both variables.
  - Find the argument-parsing site (search for the `[aA][uU][tT][oO]` inline regex via `grep -n '\[aA\]\[uU\]\[tT\]\[oO\]' skills/fix-issues/SKILL.md`). If `/fix-issues` has no script-entry parser block today (model-layer-only), add one EARLY in the skill body. **Placement rule (DA M3 round-2):** the parser block MUST be placed BEFORE ANY existing inline `[[ "$ARGUMENTS" =~ ... [aA][uU][tT][oO] ... ]]` check, AND BEFORE the first user-facing prose that references the flags. Concretely: locate via `grep -nE '\[\[ "\$ARGUMENTS" =~|\[aA\]\[uU\]\[tT\]\[oO\]' skills/fix-issues/SKILL.md | head -1` and place the new parser block strictly above that line. If no such inline check exists yet (parsing happens entirely at model layer), place the parser block immediately after the `## Arguments` section heading.
    ```bash
    # Argument parsing — extract canonical flags from $ARGUMENTS.
    AUTO_FLAG=0
    if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
      AUTO_FLAG=1
    fi
    UNATTENDED_FLAG=0
    if [[ "$ARGUMENTS" =~ (^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]($|[[:space:]]) ]]; then
      UNATTENDED_FLAG=1
    fi
    ```
  - Implementer enumerates the existing inline `auto` regex sites (via `grep -n '\[aA\]\[uU\]\[tT\]\[oO\]' skills/fix-issues/SKILL.md`) and confirms: each one either becomes a read of `$AUTO_FLAG` (if it's about auto-merge) or is rewritten in Phase 3 (if it's a model-layer prose context).
  - Update `argument-hint` (line 4) to add `[unattended]`.
  - **Token stripping (DA M4 round-2):** locate the existing `$ARGUMENTS` strip logic (if any) via `grep -nE 'sed -E.*\[aA\]|ARGUMENTS=' skills/fix-issues/SKILL.md`. Extend (or add) a strip chain to remove BOTH `auto` AND `unattended` tokens from `$ARGUMENTS` before the focus-extraction site (which extracts the "focus" string after removing known tokens). Pattern same as WI 2.2.
  - Per D8, also enumerate the for-loop site and confirm it's structural (no flag-keyed change). Per D8 round-2 correction: do NOT add an AUTO_FLAG gate to `gh issue close` — preserve the existing `case "${LP[STATUS]:-}" in merged) ... ;; *) ...` gate at lines 525–540 unchanged.

- [ ] **WI 2.4 — `/do` parser** (`skills/do/SKILL.md`, AUTO_FLAG pre-flight block introduced by cherry-picked PR #303). After Phase 1 WI 1.4, `AUTO_FLAG` exists. This WI adds `UNATTENDED_FLAG` symmetric to it:
  ```bash
  UNATTENDED_FLAG=0
  if [[ "$ARGUMENTS" =~ (^|[[:space:]])[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]($|[[:space:]]) ]]; then
    UNATTENDED_FLAG=1
  fi
  ```
  - Update `argument-hint` (line 3) to add `[unattended]` (post-#303 hint already has `[auto]`).
  - Per D11, verify the new hint length (now ~141 chars with `[unattended]`). If above a reasonable practical cap (no formal cap exists in budget doc — see WI 6.5 for the per-skill compaction decision), flag for Phase 6.

- [ ] **WI 2.5 — Mirror + version bump** for all 4 skills:
  ```bash
  # NOTE: 'do' (the skill name) is a literal list-word here. The `;` before
  # `do` (the loop keyword) is REQUIRED — without it, bash treats the second
  # `do` as the keyword and errors out. If reformatting this loop (e.g.
  # across newlines), preserve the `;`. Tested: bash 5.x parses correctly.
  for s in quickfix run-plan fix-issues do; do
    today=$(TZ=America/New_York date +%Y.%m.%d)
    hash=$(bash scripts/skill-content-hash.sh "skills/$s/SKILL.md")
    bash scripts/frontmatter-set.sh "skills/$s/SKILL.md" metadata.version "$today+$hash"
    bash scripts/mirror-skill.sh "$s"
  done
  ```
  Verify each `.claude/skills/<s>/SKILL.md` is byte-identical to source post-mirror. (Comment addresses DA M10 round-1.)
  - **Cosmetic note (DA M1 round-2):** /do may carry a same-date version bump from Phase 1's cherry-pick of #303. The Phase 2 loop re-bumps regardless — the hash will change since `UNATTENDED_FLAG` was added — and the same-date double-bump is normal (the hash captures the content delta). Not a correctness issue; documented to pre-empt verifier confusion.

### Design & Constraints

- Token regex MUST be `[uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]` (case-insensitive per-char, matches the existing `[aA][uU][tT][oO]` convention). Verified via bash 5.x smoke test that the pattern matches standalone `unattended` and does NOT match suffixes like `unattended-mode` (latter falls through to `*)` in case statements).
- Token MUST be positional, recognized anywhere in the arg vector (consistent with `auto`).
- `unattended` token consumption from description: same rule as existing `auto` — if the user's description literally contains the standalone word `unattended`, the token is consumed. Known limitation; documented in reference doc.
- Token MUST be stripped from `$ARGUMENTS` before downstream consumers (cron prompts, focus parsing, issue-number parsing) — same hygiene as `auto`/`now` stripping. Implementer verifies the existing strip logic covers `unattended`; if not, extends it.
- For `/run-plan`: `finish auto` composite hoists BOTH flags via the `if [ "$FINISH_MODE" = "finish-auto" ]; then ... fi` block. This is the load-bearing backward-compat alias.
- All 4 skills MUST land within Phase 2's PR-feature-branch state (NOT a single commit, but the phase boundary — Reviewer H3 mitigation). Phase report is written only after all 4 are wired.
- Phase 2 introduces variables but does NOT yet rewrite the model-layer "Without `auto` / With `auto`" prose — that's Phase 3. After Phase 2 the variables exist but most gate decisions are still model-layer prose; Phase 3 binds them.

### Acceptance Criteria

- AC2.1 — All 4 SKILL.md files contain `UNATTENDED_FLAG` initializer and a positional token detection arm/regex. (`grep -l UNATTENDED_FLAG skills/{quickfix,run-plan,fix-issues,do}/SKILL.md` returns 4 paths.)
- AC2.1b — Bash-pattern smoke test (per Reviewer M4 round-2): assert `bash -c 'case "unattended" in [uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]) echo match;; *) echo nomatch;; esac'` prints `match`, AND `bash -c 'case "unattended-mode" in [uU][nN][aA][tT][tT][eE][nN][dD][eE][dD]) echo match;; *) echo nomatch;; esac'` prints `nomatch`. Add to `tests/test-skill-conformance.sh` as a one-off bash-pattern guard so a future regex tweak (e.g. adding `*`) doesn't silently break the standalone-only invariant.
- AC2.2 — All 4 SKILL.md files contain `AUTO_FLAG` initializer. /quickfix and /do already have it (latter via #303 cherry-pick); /run-plan and /fix-issues are new in this phase. (`grep -l AUTO_FLAG skills/{quickfix,run-plan,fix-issues,do}/SKILL.md` returns 4 paths.)
- AC2.3 — All 4 `argument-hint` lines list `[unattended]`. (Grep recipe: `grep -E 'argument-hint.*\[unattended\]' skills/{quickfix,run-plan,fix-issues,do}/SKILL.md` returns 4 hits.)
- AC2.4 — For `/run-plan`: the `finish-auto` composite alias correctly hoists BOTH `AUTO_FLAG=1` AND `UNATTENDED_FLAG=1`. (Behavioral smoke test is **DEFERRED to Phase 7 WI 7.2** integration test which builds the static parser-block extractor — per DA M7 round-2, no existing extractor for /run-plan today. Phase 2 acceptance gates on AC2.6 + prose-presence only; the behavioral assertion lands in Phase 7.)
- AC2.5 — All 4 `.claude/skills/<s>/SKILL.md` mirrors are byte-identical to source. (`diff -q skills/<s>/SKILL.md .claude/skills/<s>/SKILL.md` returns nothing for each.)
- AC2.6 — All 4 `metadata.version` fields bumped to today's date with current hash. (`bash scripts/skill-version-stage-check.sh` passes without STOP.)
- AC2.7 — `tests/test-skill-conformance.sh` updated: new assertions confirming `UNATTENDED_FLAG` exists in each of the 4 skills, AND `AUTO_FLAG` exists in each. Add after the existing `auto-gating prose` check (currently at line ~434, but Phase 7 uses grep-recipe; this AC's grep recipe: `grep -nE 'UNATTENDED_FLAG|AUTO_FLAG' tests/test-skill-conformance.sh` shows ≥8 new assertions).

### Dependencies

- Phase 1 complete (reference doc exists for prose to link; #303 cherry-picked so /do has `AUTO_FLAG`).

### Tests

- New conformance assertions per AC2.7.
- Per-skill smoke test for `/quickfix`: existing test-harness extracts the parser (test-quickfix.sh:300-318 PARSER_SCRIPT pattern). Add fixture: dispatch with `$ARGUMENTS="<desc> unattended"`, assert `UNATTENDED_FLAG=1`. **For `/run-plan`, `/fix-issues`, `/do`:** NO equivalent extractor exists today (verified: `grep -rln "_ZSKILLS_TEST_HARNESS\|extract_parser" tests/`). Options to address DA M5 / Reviewer M1:
  - (preferred) Defer per-skill parser smoke tests to the integration test in Phase 7 WI 7.2, which uses **static parser-block extraction** (grep the SKILL.md for the regex line, eval in isolation) rather than full skill dispatch. This is what `/quickfix`'s extractor effectively does for the parser-only case.
  - Alternative: build extractors for the 3 missing skills. Heavier work, deferred unless Phase 7's static extraction proves insufficient.
- The new file `tests/test-run-plan.sh` is NOT created in this plan (research confirms it doesn't exist on main; out of scope to create — Reviewer M1).
- Full suite (`bash tests/test-all.sh`) must pass.

## Phase 3 — Model-layer prose rewrite for narrow `auto` + `unattended` gating

### Goal

Narrow `auto` semantics in `/run-plan` and `/fix-issues` to "auto-merge pass-through" by rewriting each enumerated model-layer prose site to read the new variables (Phase 2 introduced them; Phase 3 binds them). Per Reviewer H1 / DA H1: the "audit" framing is wrong — the implementer needs an **enumerated list** of prose sites. This phase provides it.

### Pre-enumerated `/run-plan` model-layer "Without/With auto" sites (verified 2026-05-16)

| File:Line | Current text snippet | New behavior |
|-----------|----------------------|--------------|
| `skills/run-plan/SKILL.md:38–40` | "Without `auto`: pauses BETWEEN phases... With `auto`: each phase runs as its own cron-fired top-level turn" | Rewrite: "Without `unattended`: pauses BETWEEN phases... With `unattended` (or the `finish auto` composite alias): each phase runs as its own cron-fired top-level turn... `auto` independently controls whether per-phase `/land-pr` dispatches request auto-merge (passes `--auto`)." |
| `skills/run-plan/SKILL.md:762–764` | "Without `auto`: tell the user... With `auto`: dispatch `/draft-plan`" | Rewrite: gate on `unattended` (this is a between-phase decision-skip). |
| `skills/run-plan/SKILL.md:797, 808` | "Without `auto`: present findings... With `auto`: if any bullet has drift" | Rewrite: gate on `unattended` (drift-acceptance is a human-review-skip). |
| `skills/run-plan/SKILL.md:906–908` | "Without `auto`: display the phase summary... With `auto`: proceed immediately" | Rewrite: gate on `unattended`. |
| `skills/run-plan/SKILL.md:1585–1586` | "Without `auto`: present findings, ask user... With `auto`: dispatch a fresh fix agent" | Rewrite: gate on `unattended` (fix-agent dispatch is a remediation-without-asking decision). |

### Pre-enumerated `/fix-issues` model-layer "Without/With auto" sites (verified 2026-05-16)

| File:Line | Current text snippet | New behavior |
|-----------|----------------------|--------------|
| `skills/fix-issues/SKILL.md:1080–1083` | "**Without `auto`:** Wait for user approval of the list... **With `auto`:** Present the ranked table, then proceed" | Rewrite to `unattended` (Phase 2 issue-list approval gate). |
| `skills/fix-issues/SKILL.md:1509–1530` | "**Auto-flag gating depends on landing mode.** Without `auto`..." | This block governs `/land-pr --auto` pass-through per landing mode. KEEP keyed on `auto` — this is the narrow `--auto` semantic D2 preserves. Update phrasing to clarify it's about merge, not approval. |
| `skills/fix-issues/SKILL.md:591–603` | `plan auto` selection gate (legacy composite phrase) | (a) The bash parser sets `UNATTENDED_FLAG=1` when `unattended` is in `$ARGUMENTS`. (b) The model-layer prose at lines 591–603 reads: "If `$UNATTENDED_FLAG=1` OR if the user invoked `plan auto` (literal substring in `$ARGUMENTS`), skip the selection-prompt and select all." The literal `plan auto` phrase is a legacy composite alias, preserved for backward compatibility. Resolution order: bash flag is checked first; literal phrase is a fallback. Implementer reads both source sites and binds the prose to this OR-rule. |
| `skills/fix-issues/SKILL.md:530–545` | `gh issue close` editorial decision | KEEP keyed on `${LP[STATUS]:-}` (the existing `case ... merged) ... ;; *) Skipping ...` gate). D8 round-2 correction: this gate is NOT currently `AUTO_FLAG`-keyed (verified `sed -n '530,545p'` 2026-05-16); do not add an AUTO_FLAG gate. LP[STATUS]-keyed gate is correct per `feedback_automerge_blocked_means_act.md`. |

### Work Items

- [ ] **WI 3.1 — `/run-plan` model-layer prose rewrite.** Walk each row in the `/run-plan` table above. For each site, rewrite the prose to gate on `unattended` (NOT `auto`) for human-review-skip semantics. Preserve `auto` gating where it genuinely controls auto-merge (e.g. add new prose at the `/land-pr` dispatch construction site stating "if `AUTO_FLAG=1`, pass `--auto` to `/land-pr`"). Find the per-phase `/land-pr` dispatch site via `grep -n 'land-pr' skills/run-plan/SKILL.md` and add the `--auto` pass-through if not present. Confirm `FINISH_MODE="finish-auto"` is referenced as the composite alias in the new prose.

- [ ] **WI 3.2 — `/run-plan` cron-prompt regeneration (EXPANDED per DA H1 round-2).** When `/run-plan` constructs ANY cron prompt, the prompt MUST be assembled from `$AUTO_FLAG`/`$UNATTENDED_FLAG`/`$FINISH_MODE` state (not from literal `auto` strings) so newly-scheduled crons are not born stale. **Pre-enumerated cron-prompt construction sites (verified via `grep -n 'Run /run-plan' skills/run-plan/SKILL.md` 2026-05-16):**

  | Line | Mode | Current literal | New (post-rewrite) |
  |------|------|-----------------|--------------------|
  | 314 | `every` (example block) | `Run /run-plan plans/FEATURE_PLAN.md auto every 4h` | Update example to `Run /run-plan plans/FEATURE_PLAN.md auto unattended every 4h` (or `unattended every 4h` if "every implies auto" per line 56). |
  | 372 | `every` (canonical construction) | `Run /run-plan <plan-file> auto every <schedule> now` | Construct from flags: include `auto` if `AUTO_FLAG=1`, include `unattended` if `UNATTENDED_FLAG=1`. Default for new `every` schedules: `auto unattended` (unattended is mandatory for cron-fired between-phase advance). |
  | 479 | comment about CronList check | `Run /run-plan <plan-file> finish auto` | Update comment to mention the composite alias preservation. |
  | 491 | comment | `Run /run-plan <plan-file> finish auto` | Same — composite preserved. |
  | 515, 544, 553, 556 | finish-mode recovery sites | `Run /run-plan <plan-file> finish auto` (matched/constructed) | Composite alias preserved as literal `finish auto`. |
  | 2077, 2128 | finish-mode chunked-cron construction | `Run /run-plan <plan-file> finish auto` | Composite alias preserved as literal `finish auto`. |

  **Regeneration rules:**
  - If `FINISH_MODE="finish-auto"` (composite alias): regen as `finish auto` (composite preserved — sets both flags downstream).
  - If `FINISH_MODE="finish-auto"` AND user explicitly added `unattended`: regen as `finish auto unattended`.
  - If `FINISH_MODE="finish-unattended"` (new explicit form): regen as `finish unattended`.
  - For `every`-mode (line 372): regen as `auto unattended every <SCHEDULE> now` for new crons (mandatory `unattended` for non-interactive between-phase advance), preserving any user-typed tokens.
  - Implementer enumerates ALL sites in the table above, updates each per rule.

- [ ] **WI 3.3 — `/run-plan` migration auto-promote (REVISED per Reviewer H3 / DA H3 round-2; drops cron-fire detection).** Round-1 attempted to scope the promote to cron-fire context via a `cron-fire-detected` predicate. Round-2 verification (`grep -nE 'cron-fire-detected|cron_fired|CRON_FIRED' skills/run-plan/SKILL.md`) confirmed no such predicate exists; `now` alone is ambiguous (used by `/run-plan ... now` interactive trigger at line 239). Inventing a detector is design-non-trivial. **Decision: drop the cron-vs-interactive distinction; always promote during the migration window.** The cost is one extra stderr NOTE on interactive `auto`-only invocations during the 3-month window; the benefit is correctness (no cron-hang) plus a 3-line implementation.

  At parser entry, after the FINISH_MODE / AUTO_FLAG / UNATTENDED_FLAG block:
  ```bash
  # MIGRATION_END_DATE: implementer sets this to today + 90 days at Phase 3
  # commit time, where today = the date of the implementer's first commit on
  # this feature branch in America/New_York. Computed as:
  #   today=$(TZ=America/New_York date +%Y-%m-%d)
  #   end=$(TZ=America/New_York date -d "$today + 90 days" +%Y-%m-%d)
  # Hardcoded value gets written verbatim into the SKILL.md prose (NOT
  # computed at runtime — agents who run on stale clocks must see the
  # same date). Example: if implementer's first commit is 2026-06-01,
  # the value is "2026-08-30".
  MIGRATION_END_DATE="<YYYY-MM-DD set at impl time>"
  if [ "$AUTO_FLAG" = "1" ] && [ "$UNATTENDED_FLAG" = "0" ] && [ "$FINISH_MODE" != "finish-auto" ]; then
    if [ "$(TZ=America/New_York date +%Y-%m-%d)" \< "$MIGRATION_END_DATE" ]; then
      UNATTENDED_FLAG=1
      echo "NOTE: 'auto' now means auto-merge ONLY (no autonomous between-phase advance). Promoting to 'auto unattended' for compatibility through $MIGRATION_END_DATE. Update your invocation (or cron prompt) to include 'unattended' explicitly. See references/auto-unattended-semantics.md." >&2
    fi
  fi
  ```
  After `MIGRATION_END_DATE`, this entire block is removed (follow-up issue tracked in "Open coordination items"). Legacy `auto`-only invocations after that date no longer get an autonomous between-phase advance; the user must type `unattended` explicitly.

- [ ] **WI 3.4 — REMOVED (consolidated into WI 3.3 per H3/DA H3 round-2).** Round-1's WI 3.4 was the interactive-WARN counterpart to WI 3.3's cron-promote. With the cron-vs-interactive distinction dropped, WI 3.3 alone fires the NOTE for all contexts (interactive + cron-fired). The single NOTE message reads "promoting to 'auto unattended'" which functions as both info and silent-fix. Implementer skips WI 3.4 entirely.

- [ ] **WI 3.5 — `/fix-issues` model-layer prose rewrite.** Walk each row in the `/fix-issues` table above. The implementer reads each source block, confirms the row's behavior categorization (approval-skip vs. merge-pass-through), and rewrites accordingly. Special handling for `plan auto`: preserve the literal phrase as a user-facing token, but the model evaluates either-or (`unattended` OR `plan auto` literal triggers selection-skip).

- [ ] **WI 3.6 — `/fix-issues` cron-prompt regeneration.** Symmetric to WI 3.2 (no composite alias to worry about — `/fix-issues` has no `finish` token). Cron prompts must carry `auto unattended` if user invoked with both. Update line ~664 area to construct from the actual flags, not literal `auto`.

- [ ] **WI 3.7 — `/fix-issues` migration auto-promote.** Symmetric to WI 3.3 (REVISED form): drops cron-fire detection; always promotes during the migration window. Same `MIGRATION_END_DATE` constant value (use the same date as /run-plan — implementer sets both to today + 90 days at Phase 3 commit time). Same NOTE message phrased for /fix-issues. /fix-issues has no `finish` mode, so omit the `FINISH_MODE != "finish-auto"` clause from the guard:
  ```bash
  MIGRATION_END_DATE="<YYYY-MM-DD set at impl time, same as WI 3.3>"
  if [ "$AUTO_FLAG" = "1" ] && [ "$UNATTENDED_FLAG" = "0" ]; then
    if [ "$(TZ=America/New_York date +%Y-%m-%d)" \< "$MIGRATION_END_DATE" ]; then
      UNATTENDED_FLAG=1
      echo "NOTE: 'auto' in /fix-issues now means auto-merge ONLY. Promoting to 'auto unattended' for compatibility through $MIGRATION_END_DATE. Update invocation/cron to include 'unattended' explicitly. See references/auto-unattended-semantics.md." >&2
    fi
  fi
  ```

- [ ] **WI 3.8 — REMOVED (consolidated into WI 3.7 per H3/DA H3 round-2).** Same rationale as WI 3.4: the cron-vs-interactive distinction is dropped; WI 3.7's NOTE fires in all contexts.

- [ ] **WI 3.9 — Mirror + version bump** for `/run-plan` and `/fix-issues` (2 skills this phase).

### Design & Constraints

- The migration auto-promote NOTE (WI 3.3 / WI 3.7) is a single line to stderr. No exit. No prompt-for-confirmation. Fires in BOTH interactive AND cron-fired contexts (the cron-vs-interactive distinction was dropped in round-2; see WI 3.3 rationale).
- The migration auto-promote is a TIME-LIMITED affordance (3 months from implementation date). After `MIGRATION_END_DATE`, removed entirely (follow-up issue).
- Cron-prompt regeneration must reconstruct from `$AUTO_FLAG`/`$UNATTENDED_FLAG`/`$FINISH_MODE` state, not from literal `$ARGUMENTS` parsing — addresses the migration cleanly. ALL enumerated sites in WI 3.2's table must be covered (no site left emitting legacy literal `auto` shape).
- The `finish-auto` composite alias is preserved indefinitely (it's the load-bearing user workflow per D2-RP).
- No change to `/land-pr` arg vector (D9).
- Per D8: in `/fix-issues`, the for-loop structure is unchanged; only the per-iteration approval gate moves to `UNATTENDED_FLAG`. The `gh issue close` editorial decision stays on `${LP[STATUS]:-}` (existing gate; D8 round-2 correction — NOT AUTO_FLAG).

### Acceptance Criteria

- AC3.1 — In `/run-plan`, each row in the Phase 3 pre-enumeration table has been rewritten. (Verifier reads each cited line and confirms the new prose gates on `unattended` for human-review-skip semantics and on `auto` for `--auto` pass-through only.)
- AC3.2 — In `/fix-issues`, same audit per the second table.
- AC3.3 — Migration auto-promote NOTE fires for both /run-plan and /fix-issues when `AUTO_FLAG=1 && UNATTENDED_FLAG=0` AND today < `MIGRATION_END_DATE`. (Smoke test: dispatch each skill with `auto` only, assert stderr contains the NOTE line AND `UNATTENDED_FLAG=1` post-parse. Per Reviewer H3 / DA H3 round-2: this is the unified replacement for round-1's separated cron/interactive WARNs.)
- AC3.4 — `MIGRATION_END_DATE` constant is set by the implementer at Phase 3 commit time per the WI 3.3 / WI 3.7 rule (today + 90 days in America/New_York, same value in both skills). Verify via `grep -n 'MIGRATION_END_DATE=' skills/{run-plan,fix-issues}/SKILL.md` returns 2 hits with identical date values.
- AC3.5 — Cron-prompt regeneration covers ALL enumerated sites in WI 3.2's table (lines 314, 372, 479, 491, 515, 544, 553, 556, 2077, 2128 per round-2 enumeration). Verify via `grep -n 'Run /run-plan' skills/run-plan/SKILL.md` returns the same line count post-rewrite, and each `every`-mode site (line 372, plus 314 example) includes `unattended` in the new shape, and each `finish`-mode site preserves the `finish auto` literal composite. New `every`-mode crons born post-landing must NOT emit legacy-shape prompts.
- AC3.6 — Both `.claude/skills/<s>/SKILL.md` mirrors byte-identical.
- AC3.7 — Both `metadata.version` fields bumped.
- AC3.8 — `tests/test-skill-conformance.sh` updated. Grep recipe (NOT line refs): existing `check fix-issues "auto-gating prose"` assertion (currently around line 434, but locate via `grep -n 'auto-gating prose' tests/test-skill-conformance.sh`) MUST be updated to assert the NEW prose pattern. Add new assertions for `unattended-gating prose` in both /run-plan and /fix-issues.

### Dependencies

- Phase 2 complete (`UNATTENDED_FLAG` and `AUTO_FLAG` exist as bash variables in both skills).

### Tests

- 2 new fixtures: `/run-plan` and `/fix-issues` invoked with `auto` only, assert auto-promote NOTE on stderr AND `UNATTENDED_FLAG=1` post-parse (per WI 3.3 / WI 3.7 unified migration promote).
- 2 new fixtures: same skills with `auto unattended` explicit, assert NO promote-NOTE (because UNATTENDED_FLAG=1 already; guard condition false).
- 1 new fixture: `/run-plan plan.md finish auto every 4h`, assert `FINISH_MODE=finish-auto`, `AUTO_FLAG=1`, `UNATTENDED_FLAG=1` (composite alias hoist works), AND no promote-NOTE (composite path bypasses migration block via `FINISH_MODE != "finish-auto"` guard).
- Cron-prompt regeneration unit test: for /run-plan, simulate construction at line 372 with various flag combos; assert the constructed prompt includes `unattended` for new `every`-mode crons.
- Conformance updates per AC3.8.
- Full suite green.

## Phase 4 — `/quickfix` grammar rework: drop `--yes`, positional booleans, delete WI 1.10 `read -r`

### Goal

Implement D1: drop `--yes`/`-y` entirely; convert `--from-here`, `--skip-tests`, `--force` to positional `from-here`, `skip-tests`, `force`; keep `--branch <name>` and `--rounds N` as `--` flags. **Per DA H7**, also DELETE the WI 1.10 `read -r` block entirely (vestigial; model-layer WI 1.5.5 + WI 1.5.5a is the production gate), removing the need for env-var test affordances.

### Work Items

- [ ] **WI 4.1 — Parser rewrite** (`skills/quickfix/SKILL.md:66-121`). Replace the existing while/case loop with a new loop that:
  - REMOVES the `--yes|-y) YES_FLAG=1 ;;` arm entirely (delete current line 84).
  - REMOVES `YES_FLAG=0` initializer (current line 69).
  - CHANGES `--from-here) FROM_HERE=1 ;;` → `[fF][rR][oO][mM]-[hH][eE][rR][eE]) FROM_HERE=1 ;;`. Case-insensitive positional. The bash case pattern matches `from-here` / `FROM-HERE` / `From-Here` literally — verified via `bash -c 'case "From-Here" in [fF][rR][oO][mM]-[hH][eE][rR][eE]) echo match;; esac'`. (Hyphen between the bracket classes is treated as a literal character, NOT inside a bracket class — corrects the round-1 draft's misstatement per Reviewer M8.)
  - CHANGES `--skip-tests) SKIP_TESTS=1 ;;` → `[sS][kK][iI][pP]-[tT][eE][sS][tT][sS]) SKIP_TESTS=1 ;;`.
  - CHANGES `--force) FORCE=1 ;;` → `[fF][oO][rR][cC][eE]) FORCE=1 ;;`.
  - KEEPS `--branch <name>` (current lines 80-83) unchanged.
  - KEEPS `--rounds N` (current lines 93-111) unchanged.
  - KEEPS positional `auto` arm (current line 92) unchanged.
  - KEEPS the Phase 2 `unattended` arm.
  - **Case-arm ordering invariant (NEW, addresses DA H4):** the migration-redirect arms from WI 4.2 below MUST be inserted as the FIRST arms in the case statement (before all other arms, including `--branch` and the positional shapes). This ensures legacy `--yes`/`--from-here`/`--skip-tests`/`--force` cannot fall through to `*)` and become silent description prose. Document this invariant in a comment at the top of the case block.

- [ ] **WI 4.2 — Migration redirects (atomic with WI 4.1).** Insert case arms catching the removed/renamed flags AS THE FIRST ARMS in the case statement:
  ```bash
  case "$arg" in
    # --- Migration redirects (MUST be first; per WI 4.2 invariant) ---
    --yes|-y)
      echo "ERROR: /quickfix '--yes' / '-y' was removed. Scope confirmation is now handled by WI 1.5.5's context-aware logic (or the 'unattended' token to skip). Re-invoke without --yes." >&2
      exit 1 ;;
    --from-here)
      echo "ERROR: /quickfix '--from-here' was replaced by positional 'from-here'. Re-invoke as: /quickfix <description> from-here" >&2
      exit 1 ;;
    --skip-tests)
      echo "ERROR: /quickfix '--skip-tests' was replaced by positional 'skip-tests'. Re-invoke as: /quickfix <description> skip-tests" >&2
      exit 1 ;;
    --force)
      echo "ERROR: /quickfix '--force' was replaced by positional 'force'. Re-invoke as: /quickfix <description> force" >&2
      exit 1 ;;
    # --- Existing/new arms below ---
    --branch) ...
  ```
  Each redirect names the EXACT corrected invocation. Hard breaks with helpful errors. Per D5 and CLAUDE.md `feedback_no_premature_backcompat.md`, no deprecation warnings.

- [ ] **WI 4.3 — `argument-hint` update** (line 3). New hint: `"[<description>] [auto] [unattended] [from-here] [skip-tests] [force] [--branch <name>] [--rounds N]"` (99 chars). Token order rationale: orthogonal autonomy pair (`auto`, `unattended`) first, then behavior modifiers (`from-here`, `skip-tests`), then escape-hatch (`force`); value-takers last. (Address Reviewer L5.) Verify against any cap (none formally; see D11).

- [ ] **WI 4.4 — Prose updates** at the parser-args listing. Update the bullet list to describe the new positional tokens (`from-here`, `skip-tests`, `force`) and the kept `--` flags (`--branch`, `--rounds`). Remove `--yes` from the bullet list. Add a one-line note: "The legacy `--yes` flag was removed; WI 1.5.5's context-aware logic + the `unattended` token cover both unambiguous-scope and explicit-bypass cases."

- [ ] **WI 4.5 — DELETE WI 1.10 `read -r` block entirely (addresses DA H7).** Per DA H7's mitigation, the WI 1.10 `read -r` confirmation prompt is itself vestigial — model-layer WI 1.5.5 (+ WI 1.5.5a from Phase 5) is the production scope-protection gate. The `read -r` only exists to support `tests/test-quickfix.sh` Case 43's literal-script extraction path. Phase 4's decision: delete the entire `if [ "$YES_FLAG" -eq 0 ]; then ... read -r answer ...` block (current lines 740–756 area) AND the corresponding decline-finalize path. The `YES_FLAG` variable goes away with WI 4.1's removal of `YES_FLAG=0`. No env-var seam is introduced (rejects round-1's Option A in favor of DA H7's cleaner alternative).

- [ ] **WI 4.6 — Rewrite or remove `tests/test-quickfix.sh` Case 43.** After WI 4.5 deletes the `read -r` block, Case 43's `--yes "fix readme typo"` invocation has nothing to bypass. Decision tree:
  - If Case 43's primary value is testing the FULL_FLOW_SCRIPT extraction (the bash-extractable end-to-end flow), it can be retained by removing the `--yes` argument and asserting that the bash-fallback flow proceeds without the `read -r` prompt (which no longer exists).
  - If Case 43's primary value is testing the WI 1.5.5 confirmation, that test now belongs at the model-layer (untestable by bash script per H6) and Case 43 is deleted.
  - **Decision:** retain Case 43 with the `--yes` removed; assert it tests the bash-extraction happy path (model already decided "y" for scope). Update the test fixture's invocation from `bash "$FULL_FLOW_SCRIPT" --yes "fix readme typo"` to `bash "$FULL_FLOW_SCRIPT" "fix readme typo"`. Update any internal assertions that expected the `read -r` to occur.

- [ ] **WI 4.6b — DELETE `tests/test-quickfix.sh` Case 49 (NEW per Reviewer H1 / DA H2 round-2).** Round-1 plan addressed only Case 43; round-2 verification (`sed -n '1420,1456p' tests/test-quickfix.sh`) confirmed Case 49 is a load-bearing **user-decline regression test** that:
  - drives `bash "$FULL_FLOW_SCRIPT" "fix cancel test" <<<"n"` (NO `--yes` flag),
  - relies on the WI 1.10 `read -r` block to consume the piped `n`,
  - asserts marker status `started → cancelled` AND `reason: user-declined`,
  - asserts branch cleanup post-decline.
  After WI 4.5 deletes the `read -r` block, Case 49 will either hang (no reader for stdin) or fail (no marker transition). The deleted block IS the production decline-finalize path Case 49 exercises.
  **Decision: DELETE Case 49 entirely.** Rationale: per WI 4.5 / DA H7, the bash-fallback decline path is removed because production scope-protection moves to model-layer (WI 1.5.5 + WI 1.5.5a). User-decline regression coverage moves to the "model-layer testability gap" already documented in Phase 5's testability caveat. The deletion is intentional and aligns with the round-1 disposition of DA H7 ("DELETE WI 1.10 read -r block entirely").
  - Delete the entire Case 49 block (test-quickfix.sh:1420–1456) AND any helper invocations only used by Case 49.
  - Also delete the corresponding marker-cancellation logic referenced at `skills/quickfix/SKILL.md:762–768` if it's no longer reachable (verify via grep).
  - AC4.13 expands to assert both Case 49 deletion AND `read -r answer` source deletion.

- [ ] **WI 4.7 — Smoke tests for new positionals + edge cases (addresses DA H4, Reviewer M8, M9, DA L4, M11).** Add fixtures verifying:
  - `/quickfix --yes` exits 1 with WI 4.2 redirect (legacy hard-break, NOT silent fall-through).
  - `/quickfix --from-here` / `--skip-tests` / `--force` similarly exit 1.
  - `/quickfix <desc> from-here` sets `FROM_HERE=1`, description unchanged.
  - `/quickfix <desc> SKIP-TESTS` sets `SKIP_TESTS=1` (case-insensitivity).
  - `/quickfix --branch force fix typo` → `BRANCH_OVERRIDE="force"`, `DESCRIPTION="fix typo"`, `FORCE=0` (--branch consumes next arg unconditionally; positional `force` does NOT fire).
  - `/quickfix fix bug --rounds force` → `DESCRIPTION="fix bug --rounds"`, `FORCE=1`, `ROUNDS=1` (greedy-fallthrough sees non-numeric "force", does NOT consume as rounds; "--rounds" appended to description; "force" matches positional arm).

- [ ] **WI 4.8 — Mirror + version bump** for `/quickfix`.

### Design & Constraints

- The `from-here` / `skip-tests` / `force` positional tokens MUST be parsed as exact strings (no abbreviation, no prefix-match). The bash case-pattern `[fF][rR][oO][mM]-[hH][eE][rR][eE]` matches the literal 9-char string case-insensitively; the `-` is a literal character between bracket classes (not inside a bracket class — corrects round-1 misstatement). Verified via `bash -c 'case "from-here" in [fF][rR][oO][mM]-[hH][eE][rR][eE]) echo match;; esac'`.
- Migration redirect arms MUST be the FIRST arms in the case statement (ordering invariant per WI 4.1) so removed flags cannot silently fall through.
- Removed flags MUST emit a redirect and exit 1 (not silently fall through to description).
- WI 1.10's `read -r` block is DELETED; no env-var seam introduced (rejects round-1's Option A per DA H7).
- All edits internal to `skills/quickfix/SKILL.md` + `tests/test-quickfix.sh`; mirror byte-identical post-edit.

### Acceptance Criteria

- AC4.1 — `/quickfix --yes` errors with the WI 4.2 redirect message and exit 1. (Smoke test.)
- AC4.2 — `/quickfix --from-here` errors with the WI 4.2 redirect message and exit 1.
- AC4.3 — `/quickfix --skip-tests` errors. `/quickfix --force` errors. (Symmetric.)
- AC4.4 — `/quickfix <desc> from-here` succeeds and sets `FROM_HERE=1` with `DESCRIPTION=<desc>`. (Smoke test with test-harness PARSER_SCRIPT extraction.)
- AC4.5 — `/quickfix <desc> SKIP-TESTS` succeeds and sets `SKIP_TESTS=1` (case-insensitivity).
- AC4.6 — `/quickfix --branch force fix typo` → `BRANCH_OVERRIDE="force"`, `DESCRIPTION="fix typo"`, `FORCE=0` (per WI 4.7).
- AC4.7 — `/quickfix fix bug --rounds force` → `DESCRIPTION="fix bug --rounds"`, `FORCE=1`, `ROUNDS=1` (per WI 4.7).
- AC4.8 — `tests/test-quickfix.sh` Case 43 rewritten per WI 4.6; passes without `--yes`.
- AC4.9 — `argument-hint` line shows the new shape (`grep "argument-hint" skills/quickfix/SKILL.md` returns the new 99-char hint).
- AC4.10 — `.claude/skills/quickfix/SKILL.md` byte-identical to source.
- AC4.11 — `metadata.version` bumped.
- AC4.12 — `tests/test-skill-conformance.sh` parser-shape assertion (locate via `grep -n '\-\-yes\|\-\-from-here' tests/test-skill-conformance.sh` — currently around line ~340, but use grep recipe) updated to drop `--yes` from the expected pattern and add positional `from-here` / `skip-tests` / `force` to the expected pattern. New negative assertion: `check_not quickfix "no --yes arm" '\-\-yes'`. New positive assertion: `check_fixed quickfix "positional from-here arm" '[fF][rR][oO][mM]-[hH][eE][rR][eE]) FROM_HERE=1'`.
- AC4.13 — WI 1.10's `read -r answer` block is DELETED (`grep -n "read -r answer" skills/quickfix/SKILL.md` returns no hits) AND Case 49 is DELETED from `tests/test-quickfix.sh` (`grep -n "Case 49\|user-decline" tests/test-quickfix.sh` returns no hits, per WI 4.6b). Marker-cancellation logic at SKILL.md:762–768 (referenced only by deleted bash path) is also removed if unreachable; verify by grep for `status: cancelled` references and confirm any survivors are model-layer-reachable.

### Dependencies

- Phase 2 complete (parser already accepts `unattended`; this phase preserves that arm while reworking neighboring arms).

### Tests

- 4 smoke tests for removed-flag redirects (AC4.1–AC4.3).
- 4 smoke tests for new positional acceptance (AC4.4–AC4.7).
- Case 43 rewritten per WI 4.6 (passes without `--yes`).
- Case 49 DELETED per WI 4.6b (no longer testable post-WI 4.5 read -r deletion; coverage moves to model-layer per Phase 5 testability caveat).
- Conformance updates per AC4.12, AC4.13.
- Full suite green.

## Phase 5 — `/quickfix` WI 1.5.5 context-aware logic + `unattended` skip

### Goal

Implement D4: WI 1.5.5 fires only when scope is ambiguous (multi-file dirty tree OR description doesn't word-boundary-match the single dirty file). Implement D3-QF: `unattended` forces the SKIP branch unconditionally. Preserves the load-bearing protection from PR #49 + `skills/quickfix/SKILL.md:542-547` rationale while making `unattended` non-vestigial.

### Work Items

- [ ] **WI 5.1 — Add WI 1.5.5a scope-ambiguity detector** at the top of WI 1.5.5 (model-layer prose). Inserted before the existing "show the user the full dirty-file list" step at `skills/quickfix/SKILL.md:516`.

  **Model-layer evaluation rule (DA M2 round-2 mitigation):** WI 1.5.5a is markdown prose evaluated by the model. The model reads `UNATTENDED_FLAG`'s value from the **rendered context** — i.e. the WI 1.5.5 prose itself MUST instruct the parser block (Phase 2 WI 2.1) to echo the flag value to stderr so the model sees it in its turn context. Add to the Phase 2 WI 2.1 parser block, immediately after the `UNATTENDED_FLAG=1` arm fires: `echo "UNATTENDED_FLAG=$UNATTENDED_FLAG" >&2`. The model then reads that line in its turn input and conditions WI 1.5.5a accordingly. This makes `$UNATTENDED_FLAG` actually evaluable at the model layer (otherwise the markdown `$` would be aspirational; the model can't run bash to expand it).

  Inserted prose:
  ```markdown
  ### WI 1.5.5a — Scope-ambiguity check (model-layer)

  Compute `$SCOPE_AMBIGUOUS` from `$DIRTY_FILES`, `$DESCRIPTION`, and
  `$UNATTENDED_FLAG` (the model reads `UNATTENDED_FLAG`'s value from the
  parser-block's stderr echo line `UNATTENDED_FLAG=N` emitted at parser
  exit — see WI 2.1 amendment):

  - If `UNATTENDED_FLAG=1` → `SCOPE_AMBIGUOUS=0` UNCONDITIONALLY (explicit
    user opt-in per D3-QF; skip confirmation, emit stderr NOTE: "NOTE: WI
    1.5.5 scope-confirmation skipped (unattended).").
  - Else if `$DIRTY_FILES` contains 2 or more entries → `SCOPE_AMBIGUOUS=1`.
  - Else if `$DIRTY_FILES` contains exactly 1 entry:
    - Compute `FNAME = basename of the single dirty file`.
    - Compute `FNAME_NORMALIZED = FNAME with hyphens replaced by spaces`.
    - Compute `FPATH = full path of the single dirty file`.
    - WORD-BOUNDARY substring match (case-insensitive): token is preceded
      and followed by whitespace, punctuation, or string boundary. If
      `$DESCRIPTION` contains `FNAME` as a word-boundary substring OR
      contains `FNAME_NORMALIZED` as a word-boundary substring OR contains
      `FPATH` as a substring → `SCOPE_AMBIGUOUS=0`. (Word-boundary tightens
      raw substring per Reviewer M7 / DA M8 to avoid `fix foobar` matching
      file `foo`. Hyphen-space normalization handles `the build` ↔
      `the-build.sh`.)
    - Otherwise → `SCOPE_AMBIGUOUS=1`.
  - If `$DIRTY_FILES` is empty (agent-dispatched mode) → WI 1.5.5 does not
    apply (this WI only runs in user-edited mode). **Mode variable per
    DA L1 round-2:** /quickfix WI 1.5 resolves invocation mode via the
    `$DIRTY_FILES` empty-vs-nonempty check, NOT a separate `MODE` variable.
    Read by reference to `$DIRTY_FILES` directly. **Caveat per
    Reviewer H7:** verify clean-tree-on-entry was confirmed during WI 1.5
    mode resolution; if not, the agent-mode assumption is unsafe. Add a
    one-line assertion at WI 1.5 mode-resolution that clean-tree-on-entry
    is explicit before falling into agent-mode.

  When `SCOPE_AMBIGUOUS=0`, skip WI 1.5.5's user-confirmation prompt; emit
  a single-line stderr NOTE describing why (one of: "unattended override",
  "single dirty file '<FNAME>' named in description") and proceed to WI 1.6.

  When `SCOPE_AMBIGUOUS=1`, proceed with the existing WI 1.5.5 confirmation
  steps (1–4 below).
  ```

  **Parser-block amendment to Phase 2 WI 2.1 (this WI back-edits):** after the `UNATTENDED_FLAG=1` arm fires (and again at parser exit unconditionally), emit `echo "UNATTENDED_FLAG=$UNATTENDED_FLAG" >&2` so the model sees the value. Optional alternative (implementer choice): emit a single combined line `echo "FLAGS: AUTO_FLAG=$AUTO_FLAG UNATTENDED_FLAG=$UNATTENDED_FLAG" >&2` at parser exit.

- [ ] **WI 5.2 — Update WI 1.5.5 rationale prose** (`SKILL.md:542-547`). Append a paragraph:
  > **Why context-aware:** the failure mode WI 1.5.5 prevents — model loose-matching `$DESCRIPTION` to dirty files and bundling unrelated work — applies when scope is ambiguous (multi-file or description doesn't name the file). When the dirty tree has exactly one file AND the user named it in the description, scope is unambiguous. WI 1.5.5a's detector preserves the protection where it matters and removes it where it doesn't. The `unattended` token (D3-QF) provides an explicit user opt-out: typing `unattended` is an explicit risk acceptance that the model will scope correctly. **Known false-friction cases:** descriptions like "fix scripts" or "update docs" that name a directory but not a basename will fire WI 1.5.5 even when the single dirty file is unambiguously implied. We accept the friction in favor of conservative-when-uncertain protection; users facing this case can type `unattended`. **Known protection-loss case:** if the user types `unattended` and the model scopes incorrectly, work bundling can occur — explicit opt-in is the explicit acceptance.

- [ ] **WI 5.3 — Coupling rule note.** Add a one-line note at the top of WI 1.5.5: `Note: this WI is bypassed by the 'unattended' positional token (per D3-QF). The unattended token forces WI 1.5.5a SCOPE_AMBIGUOUS=0 unconditionally.` (Replaces round-1's "NOT bypassed" rule.)

- [ ] **WI 5.4 — Update WI 1.10 prose post-deletion.** Phase 4 deleted the `read -r` block; WI 1.10 prose is updated to remove references to YES_FLAG / read -r. The vestigial-fallback rationale paragraph is rewritten to describe the new state: production model-driven invocations use WI 1.5.5 + WI 1.5.5a entirely at the model layer; the bash-extraction test path (Case 43) tests the happy bash-fallback flow without scope-prompt.

- [ ] **WI 5.5 — Mirror + version bump** for `/quickfix`.

### Design & Constraints

- The word-boundary match uses bash regex `[[:space:][:punct:]]|^|$` boundary semantics or equivalent; implementer chooses the exact form. Hyphen-space normalization is one substitution: `FNAME_NORMALIZED=$(echo "$FNAME" | tr - ' ')`.
- No regex-fuzz, no stemming. Word-boundary substring + hyphen normalization. The model is permitted to be conservative: if uncertain, treat as ambiguous and fire WI 1.5.5.
- The skip-NOTE to stderr is mandatory — agents reading session transcripts must see when WI 1.5.5 was skipped (for triage if scope ends up wrong).
- WI 1.5.5a is model-layer prose, not bash. Implementer agent does not add a bash detector; the model evaluates the conditions and proceeds accordingly. **Testability caveat (addresses Reviewer H6, DA M1):** WI 1.5.5a behavior cannot be automatically tested by bash test scripts (it's model-layer). Phase 5's tests instead verify (a) the prose exists and reads `$UNATTENDED_FLAG`; (b) the WI 1.10 bash-fallback path (post-deletion: nothing to test); (c) `unattended` correctly sets `UNATTENDED_FLAG=1` (already covered by Phase 2 + 4 fixtures). The "manual verifier check" gate per AC5.4 is the formal validation for model-layer behavior.
- WI 1.5.5a respects `$UNATTENDED_FLAG` per D3-QF (changes round-1 stance).

### Acceptance Criteria

- AC5.1 — WI 1.5.5a section exists in `skills/quickfix/SKILL.md` with the detector spec (including `$UNATTENDED_FLAG` short-circuit).
- AC5.2 — Rationale appended to WI 1.5.5 explaining the load-bearing-where-it-matters logic + the known false-friction and protection-loss cases.
- AC5.3 — Coupling rule note present at top of WI 1.5.5 stating `unattended` bypasses (per D3-QF).
- AC5.4 — Manual test (verifier runs through `/quickfix` in a controlled fixture):
  - Scenario 1 — dirty tree has only `foo.md`, description "fix typo in foo.md" → WI 1.5.5a NOTE fires (basename-in-description), WI 1.5.5 confirmation skipped.
  - Scenario 2 — dirty tree has `foo.md` + `bar.md`, description "fix typo in foo.md" → WI 1.5.5 fires (multi-file ambiguous).
  - Scenario 3 — dirty tree has only `foo.md`, description "update headings" → WI 1.5.5 fires (description doesn't name file).
  - Scenario 4 — dirty tree has only `foo.md`, description "update headings unattended" → WI 1.5.5a NOTE fires with "unattended override" reason, WI 1.5.5 confirmation skipped.
  - Scenario 5 — dirty tree has only `the-build.sh`, description "the build" → WI 1.5.5a NOTE fires (hyphen-space normalization).
  - Scenario 6 — dirty tree has only `foo.md`, description "fix foobar" → WI 1.5.5 fires (word-boundary mismatch: "foo" not preceded/followed by boundary in "foobar").
  Verifier confirms all 6 by reading the prose for each condition.
- AC5.5 — `.claude/skills/quickfix/SKILL.md` byte-identical.
- AC5.6 — `metadata.version` bumped.
- AC5.7 — `tests/test-quickfix.sh` adds three new fixtures verifying (a) WI 1.5.5a section exists at expected position via grep; (b) prose references `$UNATTENDED_FLAG`; (c) the unattended-override NOTE phrasing exists in prose. (Static-grep fixtures, not behavioral — per testability caveat.)

### Dependencies

- Phase 2 complete (`UNATTENDED_FLAG` exists in `/quickfix`, so D3-QF wiring has a referent).
- Phase 4 complete (WI 1.10 `read -r` block deleted, simplifying the WI 5.4 rewrite).

### Tests

- 3 new fixtures per AC5.7 (static prose-presence).
- Existing WI 1.5.5 bash fixtures (if any) re-checked for compatibility post-`read -r` deletion.
- Manual model-layer verification per AC5.4 (verifier-driven).
- Full suite green.

## Phase 6 — `/do` `unattended` parity (rebases on #303's `auto` work)

### Goal

Add `/do unattended` recognition (UNATTENDED_FLAG was wired in Phase 2 WI 2.4; this phase confirms downstream prose binding). `/do auto` was cherry-picked in Phase 1 WI 1.4. Phase 6 is now substantially smaller than the round-1 draft because the PR #303 coordination ambiguity is resolved.

### Work Items

- [ ] **WI 6.1 — Verify Phase 2 + Phase 1 outputs.** Confirm:
  - `grep -n 'AUTO_FLAG\|UNATTENDED_FLAG' skills/do/SKILL.md` returns initializer + parser-block hits for both.
  - `argument-hint` line 3 includes both `[auto]` and `[unattended]`.
  - `modes/pr.md` (from #303) reads `AUTO_FLAG` correctly.

- [ ] **WI 6.2 — Decide and document `/do unattended` semantics.** Per Reviewer H4, this is a planner-locked decision: `/do` has no current model-layer confirmation gate (verified: `grep -n 'confirm\|ready to land\|approval' skills/do/SKILL.md` returns no hits per research summary §3 line 54). **Decision (lock D11-Do):** `/do unattended` is a recognized FORWARD-PLACEHOLDER. The token is parsed, sets `UNATTENDED_FLAG=1`, and is included in argument-hint, but currently no gate reads it. This is documented explicitly in the reference doc + skill prose so users know not to expect behavior beyond auto-merge (when combined with `auto`). When `/do` grows a gate worth bypassing (e.g. a "ready to land?" confirmation in a future plan), that gate keys on `UNATTENDED_FLAG`; this plan's wiring is forward-compatible.
  - Update `/do` prose at the parser-options area: `**unattended** (optional, positional, case-insensitive) — currently a forward-placeholder for skill-internal gate bypass. /do has no confirmation gate today; this token is recognized for cross-skill consistency. Composes with 'auto' which independently controls /land-pr auto-merge. See references/auto-unattended-semantics.md.`
  - Update the reference doc's `/do unattended` cell with the forward-placeholder semantic.

- [ ] **WI 6.3 — Argument-hint length check (per D11).** Post-Phase-2 hint is ~141 chars. **Re-grep step (Reviewer L4 round-2):** before applying the soft ≤150 cap, run `grep -iE 'argument-hint|character|cap|length' references/skill-description-budget.md` to confirm no formal cap was added in the interim (round-1 verified none existed as of 2026-05-16, but the budget doc may have been updated). If a formal cap exists, honor it. If none, apply the soft ≤150 guideline.
  If above 150, options: shorten `[every SCHEDULE]` → `[every SCH]`, or drop `[push]` since `pr` mode subsumes it. **Decision:** if length > 150, drop `[every SCHEDULE]` from the hint and add a one-line prose note that scheduling is documented in the args section (the bracket is informational). Implementer reports the actual length and decision.

- [ ] **WI 6.4 — Mirror + version bump** for `/do`. (Phase 2 also bumps; Phase 6's bump only fires if WI 6.2/WI 6.3 add new prose to /do beyond Phase 2.)

### Design & Constraints

- `/do unattended` is a forward-placeholder per D11-Do — no current gate, recognized for consistency.
- `/do` PR mode invariants from CLAUDE.md (5 PR-landing-caller skills, conformance-locked) remain intact.

### Acceptance Criteria

- AC6.1 — `/do` SKILL.md contains both `AUTO_FLAG` (from #303 cherry-pick) and `UNATTENDED_FLAG` (from Phase 2 WI 2.4) initializers and parser arms.
- AC6.2 — `argument-hint` includes `[auto]` and `[unattended]`.
- AC6.3 — `/do <task> auto pr` (or equivalent) dispatches `/land-pr` with `--auto` set, per #303's wiring. (Smoke test.)
- AC6.4 — `/do <task> unattended` is parsed (`UNATTENDED_FLAG=1`) and documented as a forward-placeholder.
- AC6.5 — Reference doc updated to reflect `/do unattended` forward-placeholder semantic.
- AC6.6 — `.claude/skills/do/SKILL.md` byte-identical.
- AC6.7 — `metadata.version` bumped (if WI 6.2/6.3 added prose beyond Phase 2).
- AC6.8 — `tests/test-skill-conformance.sh` updates: new assertion confirming `UNATTENDED_FLAG` parser arm exists in /do; the existing /do `AUTO_FLAG` assertion (from #303) is preserved. (Grep recipe: `grep -n 'AUTO_FLAG\|UNATTENDED_FLAG.*do' tests/test-skill-conformance.sh`.)
- AC6.9 — `tests/test-do.sh` adds smoke fixtures for `unattended` (auto already covered by #303's added tests cherry-picked in Phase 1).

### Dependencies

- Phase 2 complete (UNATTENDED_FLAG exists in `/do`).
- Phase 1 complete (#303 cherry-picked; #303 PR closed).

### Tests

- 1 new fixture in `tests/test-do.sh` (unattended parsing).
- Conformance updates per AC6.8.
- Full suite green.

## Phase 7 — Conformance + integration tests + cron migration + docs sweep

### Goal

Lock all the new conventions in `tests/test-skill-conformance.sh`. Add an integration test exercising `auto`/`unattended` across all 4 skills. Implement the **one-shot CronList migration script** per D5. Update top-level docs. Final mirror verification. **All conformance assertions cite by grep recipe, not by line number** (per Reviewer H5 / DA M3 — line numbers drift).

### Work Items

- [ ] **WI 7.1 — Conformance assertion sweep (grep-recipe-based).** Touch the following sites in `tests/test-skill-conformance.sh` and ensure each new convention is locked. **NO line numbers cited; use grep recipes to locate.**
  - `grep -n 'argument-hint' tests/test-skill-conformance.sh` → for each /quickfix, /run-plan, /fix-issues, /do hint assertion (if present today; if absent, add new): assert the new hint shape. (/quickfix's new hint = 99 chars per WI 4.3.)
  - `grep -n 'auto-gating prose' tests/test-skill-conformance.sh` → update existing /fix-issues `auto-gating prose` assertion to reflect the new prose (gates on `unattended` for approval, `auto` for merge-pass-through).
  - Add NEW assertions: `check quickfix "positional from-here arm" '\[fF\]\[rR\]\[oO\]\[mM\]-\[hH\]\[eE\]\[rR\]\[eE\])'`; similar for skip-tests, force; for unattended in all 4 skills.
  - Add NEW negative assertion: `check_not quickfix "no --yes arm" '\-\-yes'`.
  - For each of the 4 skills, add a `check_fixed <skill> "UNATTENDED_FLAG initializer" 'UNATTENDED_FLAG=0'`.
  - For /run-plan: add `check_fixed run-plan "finish-auto composite hoists both flags" 'FINISH_MODE.*finish-auto.*AUTO_FLAG=1.*UNATTENDED_FLAG=1'` (the composite block).
  - Locate the mirror byte-identity assertion via `grep -n 'mirror\|byte-ident\|diff -q.*claude' tests/test-skill-conformance.sh` (research summary references `:1995-2020` — locate actual line and verify).
  - Implementer documents the count delta in the PR body and the verifier confirms exact assertion count.

- [ ] **WI 7.2 — Integration test (`tests/test-auto-unattended-integration.sh`).** Per Reviewer M2 / DA M5: full behavioral parser-replay is heavy (requires 3 new extractors). Decision: **static parser-block extraction** approach. The test:
  - For each of 4 skills, greps the SKILL.md for the parser block(s) that handle `auto`/`unattended` (regex pattern: `AUTO_FLAG=|UNATTENDED_FLAG=|FINISH_MODE=`).
  - Extracts each parser block into a temp file.
  - Wraps it in a test harness (sets `ARGUMENTS=...`, sources the block, prints `$AUTO_FLAG $UNATTENDED_FLAG $FINISH_MODE`).
  - Asserts the expected output for each of these arg vectors:
    - `(none)` → `AUTO_FLAG=0, UNATTENDED_FLAG=0`
    - `auto` → `AUTO_FLAG=1, UNATTENDED_FLAG=0`
    - `unattended` → `AUTO_FLAG=0, UNATTENDED_FLAG=1`
    - `auto unattended` → `AUTO_FLAG=1, UNATTENDED_FLAG=1`
    - `unattended auto` → `AUTO_FLAG=1, UNATTENDED_FLAG=1` (order-insensitivity)
    - `AUTO UNATTENDED` → `AUTO_FLAG=1, UNATTENDED_FLAG=1` (case-insensitivity)
  - For /run-plan: additionally assert `finish auto` → `FINISH_MODE=finish-auto, AUTO_FLAG=1, UNATTENDED_FLAG=1` (composite alias).
  - Total: 6 base × 4 skills = 24 fixtures + 1 /run-plan composite = 25.
  - This is a STRUCTURAL test (extracts parser blocks, evaluates in isolation); it does NOT exercise full skill dispatch. Rationale: full dispatch requires 3 new extractor scaffolds (DA M5); structural extraction is what `/quickfix`'s existing extractor effectively does.

- [ ] **WI 7.3 — Model-layer CronList migration runbook in `/update-zskills` (REVISED per Reviewer H2 round-2; NOT a bash script).** Round-1 specified `scripts/migrate-auto-unattended-crons.sh`, but verification (`grep -rn "CronList\|CronCreate\|CronDelete" scripts/` returns 0 hits; `grep -rn "CronList" skills/` returns model-layer prose only) confirms `CronList`/`CronDelete`/`CronCreate` are **model-layer MCP tools**, not bash CLIs. A bash script cannot invoke them. **Reframed approach:** add a model-layer runbook to `skills/update-zskills/SKILL.md` (or its modes dir if applicable). Step (added as a new Step after existing install steps):
  > **Step N — Cron auto/unattended migration.** If upgrading across the `auto`/`unattended` split (PR <NN> landing), the model performs a one-shot cron audit:
  > 1. Invoke `CronList` to list all cron jobs.
  > 2. For each job whose prompt matches `Run /(run-plan|fix-issues) ... auto ...` AND does NOT contain `unattended` AND does NOT match the `finish auto` composite (composite is preserved), construct the new prompt by appending `unattended` (placement: after `auto`, before `every`).
  > 3. Present the proposed diff to the user (old prompt → new prompt) for confirmation, ONE cron at a time or as a batch.
  > 4. On user confirmation, invoke `CronDelete <job-id>` then `CronCreate` with the rewritten prompt and the same schedule.
  > 5. Report a summary: N crons audited, M rewritten, K preserved (composite-alias matches).
  > Post-migration crons have `unattended` explicitly; subsequent `/update-zskills` runs no-op this step.
  - **Runtime safety net:** users who never re-run `/update-zskills` during the 3-month migration window are still covered by WI 3.3 / WI 3.7's runtime auto-promote. After `MIGRATION_END_DATE`, that promote is removed and legacy crons will hang; the follow-up issue at landing-time tracks both removal of the promote AND a final reminder for users who haven't migrated. (Addresses DA L3 round-2.)

- [ ] **WI 7.4 — CLAUDE.md addition.** Add a one-paragraph rule under a NEW top-level section `## auto and unattended tokens` (NOT under `## Git Rules` — addresses DA L1). Content per WI 1.2 (≤15 lines, includes anti-pattern callout, links to reference doc):
  > **`auto` and `unattended` tokens.** All 4 PR-landing callers (`/quickfix`, `/run-plan`, `/fix-issues`, `/do`) accept two orthogonal positional tokens: `auto` (auto-merge the resulting PR) and `unattended` (skip skill-internal human-review gates). They are independent — typing one does not imply the other.
  >
  > **Anti-pattern: `unattended` alone is NOT full autonomy.** `/fix-issues 5 unattended` skips approval gates but does NOT auto-merge. PRs sit at `pr-ready` waiting for manual merge. For fully unattended sprints, use `/fix-issues 5 auto unattended`.
  >
  > `/run-plan` preserves the legacy `finish auto` composite alias (sets both flags). See `references/auto-unattended-semantics.md` for the per-skill gate table.

- [ ] **WI 7.5 — README update (if README mentions skill grammar).** Grep recipe: `grep -nE '\-\-yes|\-\-from-here|\-\-skip-tests|\-\-force\b' README.md`. If any hits in skill-grammar context, update. If no hits, no change. (Address Reviewer L3.)

- [ ] **WI 7.6 — Final mirror verification.** Run `for s in quickfix run-plan fix-issues do; do bash scripts/mirror-skill.sh "$s"; done` and confirm `git diff` is empty (mirrors were already up-to-date from earlier phases).

- [ ] **WI 7.7 — Full conformance + full test suite.** `bash tests/test-skill-conformance.sh` passes. Per CLAUDE.md, capture output: `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; bash tests/test-all.sh > "$TEST_OUT/.test-results.txt" 2>&1`.

- [ ] **WI 7.8 — Version bumps.** Per skill versioning rule, any prose change in this phase to a SKILL.md requires a bump. CLAUDE.md changes do not bump skill versions; the migration script is new infrastructure (no skill version bump). Verify via `bash scripts/skill-version-stage-check.sh`.

### Design & Constraints

- Phase 7 is the conformance-lockstep phase. All prior phases' assertions land here in one consolidated diff to `tests/test-skill-conformance.sh`.
- ALL line-number references replaced by grep recipes (line-drift-immune per Reviewer H5).
- The integration test (WI 7.2) is the cross-skill safety net via structural extraction (not behavioral replay).
- The model-layer CronList migration runbook (WI 7.3 round-2 reframe) is the missing piece from D5's cron-survival promise. NOT a bash script (CronList is MCP).
- Phase 7 adds prose to `/update-zskills` SKILL.md (Step N migration runbook); that triggers a metadata.version bump for /update-zskills per WI 7.8.

### Acceptance Criteria

- AC7.1 — `tests/test-skill-conformance.sh` assertion count changed as expected (count delta documented in PR body; verifier confirms via `grep -c '^check' tests/test-skill-conformance.sh` before/after).
- AC7.2 — `tests/test-auto-unattended-integration.sh` exists with 25 fixtures, all pass via static parser-block extraction.
- AC7.3 — `CLAUDE.md` contains the new `## auto and unattended tokens` section with the anti-pattern callout.
- AC7.4 — README updated if needed (or no-op documented per grep recipe).
- AC7.5 — All 4 mirrors byte-identical (verified by WI 7.6's `for s in ...; bash scripts/mirror-skill.sh "$s"; done` output showing empty git diff). (Reviewer L3 round-2: kept as AC for explicit verification; WI 7.6 is the action, AC7.5 is the assertion.)
- AC7.6 — `bash tests/test-skill-conformance.sh` exit 0.
- AC7.7 — `bash tests/test-all.sh` exit 0 (captured to `$TEST_OUT/.test-results.txt`).
- AC7.8 — `bash scripts/skill-version-stage-check.sh` passes (no stale versions).
- AC7.9 — `skills/update-zskills/SKILL.md` (or appropriate mode file) contains the new "Cron auto/unattended migration" step per WI 7.3 round-2 reframe. Grep recipe: `grep -n "Cron auto/unattended migration\|auto-unattended split" skills/update-zskills/SKILL.md` returns hits. NO bash script is created (round-2 correction: CronList is model-layer MCP, not a bash CLI).
- AC7.10 — Step matches WI 7.3's 5-step runbook (CronList → match → diff → confirm → CronDelete+CronCreate → report). Verify by reading the prose.

### Dependencies

- Phases 1–6 complete.

### Tests

- New integration test per WI 7.2.
- Full conformance + full suite green per AC7.6 + AC7.7.
- Migration runbook: manual test by verifier (read the new `/update-zskills` step end-to-end; confirm the 5-step model-layer flow makes sense; verifier optionally invokes `CronList` in a session to confirm tool availability). No bash-script test (no script exists per WI 7.3 round-2 reframe).
- No additional skill fixtures beyond WI 7.2 — earlier phases supplied their own per-skill smoke fixtures.

## Open coordination items (not phases — flagged for orchestrator)

- **PR #303 (`/do auto`)** — RESOLVED at Phase 1 (closed with redirect, wiring cherry-picked). No coordination burden at Phase 6.
- **Issue #293 (Approach B native multi-mode)** — out of scope; flagged in Phase 1 reference doc that this plan's grammar cleanup makes Approach B easier later.
- **PR #309 serial-loop rule** — preserved by D8. Phase 2's `unattended` wiring in `/fix-issues` MUST NOT alter the for-loop into parallel dispatch. Verifier reads `/fix-issues` for-loop site in Phase 2 verification and confirms.
- **Cron migration tail.** D5's `MIGRATION_END_DATE` constant (3 months from implementer's first-commit date in America/New_York, set at Phase 3 commit time per WI 3.3) sets the auto-promote sunset. A follow-up issue should be filed at landing-time to track:
  - Removal of the WI 3.3 / WI 3.7 auto-promote block from /run-plan and /fix-issues parsers after the date passes.
  - **Final-reminder audit (DA L3 round-2):** users who never re-run `/update-zskills` during the window rely entirely on the runtime auto-promote (WI 3.3 / WI 3.7). The follow-up issue includes a one-line audit step (e.g. `grep -l 'auto every' .claude/zskills-config.json` or equivalent post-landing inventory) to detect this user class and ping them before MIGRATION_END_DATE.

## Plan Quality

**Drafting process:** `/draft-plan` with 2 rounds of adversarial review (reviewer + devil's-advocate agents in parallel per round) + 2 refinement passes. Each round honored the verify-before-fix discipline.

**Convergence:** Converged at round 2 (orchestrator's judgment per /draft-plan Phase 5 convergence rule). Round 3 was projected to find ≤10 LOW-severity polish issues only; marginal value below context cost.

**Remaining concerns (2 LOW, justified-not-fixed):**
- DA round-2 M1: cosmetic note about `metadata.version` double-bump if implementer makes the version edit + the prose edit in two separate commits per skill. Mitigation: Phase-N AC names "single commit per skill including version bump." Not blocking.
- DA round-2 L2: grep-mechanical limit on one markdown-table-cell assertion in WI 7.2 (test can't grep-match a specific table cell shape, only the whole row). Workaround documented inline; doesn't change behavior.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 22 (8H, 9M, 5L)   | 22 (7H, 11M, 4L)          | 38 fixed, 6 justified-not-fixed |
| 2     | 12 (3H, 5M, 4L)   | 14 (4H, 7M, 3L)           | 24 fixed, 2 justified-not-fixed |

**Round 1 → Round 2 trajectory:** ~45% reduction in total findings; all round-1 HIGHs resolved; round-2 HIGHs were surgical gaps from the round-1 structural rewrite (e.g., Case 49 cascade from WI 1.10 deletion, fictional `cron-fire-detected` predicate, fictional bash-CLI migration script). No round-1 issues regressed.

**Trust signals for the implementing agent:**
- The central round-1 factual error (assumed `AUTO_FLAG` existed in /run-plan and /fix-issues; reality: only in /quickfix) was verified by both reviewers and corrected with per-skill actual mechanisms in Phase 2.
- All conformance test references use grep recipes (not line numbers) to prevent drift bit-rot.
- The cron-migration story is a single unified runtime auto-promote (no fictional detection predicate, no fictional bash CLI) plus a model-layer prose runbook in `/update-zskills`.

