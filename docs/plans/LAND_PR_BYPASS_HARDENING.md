---
title: Close /land-pr Bypass Hole — Caller Tracker Parity + PreToolUse Hook
created: 2026-05-12
status: active
---

# Plan: Close /land-pr Bypass Hole — Caller Tracker Parity + PreToolUse Hook

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

Three agent bypasses of `/land-pr` in a single session (PRs #218, #221, #223
on 2026-05-10/11) proved that the prose-only resolution from PR #187 / issue
#185 does not propagate. This plan closes the hole structurally with two
coupled deliverables:

1. **A new PreToolUse hook** — `block-bypassed-land-pr.sh` denies all
   direct `gh pr create` and `gh pr merge --auto` from the agent's Bash
   tool. **Unconditional deny**, because every legitimate site lives
   inside a wrapper script (`skills/land-pr/scripts/pr-push-and-create.sh:142`
   and `pr-merge.sh:87`) — the PreToolUse Bash hook sees `bash $script`,
   never the inner `gh` call. There are no legitimate agent-typed cases.
   The STOP message branches on tracking state to give the right recovery
   instruction.

2. **Caller tracker parity** — extend the `requires.land-pr.<id>` /
   `--tracking-id` pattern that `/run-plan` PR-mode already partially
   wires (commit `2bdbeda`, PR #219; see `skills/run-plan/SKILL.md:851-855`
   and `skills/run-plan/modes/pr.md:342`) across the other four callers.
   This plan ALSO completes /run-plan's wiring by adding the missing
   `branch:` field to its requires marker and the missing explicit-
   finalize cleanup of the marker at end of caller-loop (Round 3 gaps
   surfaced by R-3-1 + DA-3-4):
   `/commit pr`, `/do pr`, `/quickfix`, `/fix-issues pr`. The receiving
   infrastructure in `/land-pr` already exists
   (`skills/land-pr/SKILL.md:50-53, 87, 510-538`). The four callers also
   write per-skill `fulfilled.<skill>.<id>` completion markers, mirroring
   `/quickfix`'s existing pattern (`skills/quickfix/SKILL.md:637`,
   `:653-677`) so the dashboard's activity feed sees one event per
   completed skill run (#228 Part B literal AC).

**Key architectural insight (codebase agent §B, domain agent §G/H):**
`/land-pr`'s own `gh pr create` lives in
`skills/land-pr/scripts/pr-push-and-create.sh:142`, NOT in `SKILL.md` bash
fences. The PreToolUse hook intercepts Bash *tool* invocations; the inner
`gh` calls are children of `bash $script` and never reach the hook. The
wrapper-script architecture IS the de-facto carve-out — no marker-based
existence check is needed at the carve-out point. This collapses the
original "started-vs-complete marker" design question (orchestrator's Q1):
markers don't gate the hook; they only diagnose its STOP message.

**Cross-cutting dependency on Wave 1 (#228 Part A):** This plan introduces
new `fulfilled.<skill>.<id>` and `fulfilled.land-pr.<id>` markers. The
existing `skills/update-zskills/scripts/clear-tracking.sh` preserves only `fulfilled.run-plan.*`
(`skills/update-zskills/scripts/clear-tracking.sh:48-52`). Wave 1's widening is **out of scope
for this plan body** per the orchestrator brief, BUT this plan includes
a **narrow-scope** preservation patch for the two marker families it
introduces (Phase 3 work item) so the dashboard surfacing and hook STOP
diagnostics do not silently degrade if Wave 1 lands later. Wave 1's
broader widening will subsume this narrow patch; the narrow patch is
strictly a subset.

**Out of scope** (explicitly):
- Widening `skills/update-zskills/scripts/clear-tracking.sh` preservation to ALL `fulfilled.*.*`
  (issue #228 Part A, Wave 1).
- `/commit pr` Step 6 CI-poll skip enforcement (issue #133 — same shape,
  different bypass target).
- Pre-flight enforcement for multi-agent skills broadly (issue #143).
- CLAUDE.md / CLAUDE_TEMPLATE.md prose changes. The structural hook makes
  the prose rule (CLAUDE.md:140, CLAUDE_TEMPLATE.md:171) belt-and-suspenders
  rather than load-bearing; we leave the prose intact (Plan A precedent).

## Decisions

**D1. Hook decision is unconditional deny on `gh pr (create|merge --auto)`
from agent Bash.** Tokenize-walk via a new
`is_gh_pr_subcommand_in_chain` matcher. There are no legitimate agent-Bash
sites for these verbs — the wrapper-script architecture handles all
legitimate cases. The hook does NOT consult tracking markers to make
its allow/deny decision. (R-1-7 noted: PreToolUse hooks compose additively;
"first-match-wins" is not the semantic. Order is cosmetic — we place this
hook last for diff-readability.) Single hook satisfies orchestrator C1.

**D2. Tracking markers are diagnostic + dashboard, not gating.**
- `requires.land-pr.<id>` (caller writes before /land-pr dispatch) →
  signals "caller is mid-flight in a /land-pr attempt." Used by the hook
  only to choose Pattern-1 vs Pattern-2 STOP-message wording.
- `fulfilled.land-pr.<id>` (`/land-pr` writes at Step 8b on row-6 merge
  success; existing infrastructure unchanged) → signals "PR merged on
  main with passing CI." Dashboard event.
- `fulfilled.<skill>.<id>` (caller writes at successful skill completion;
  new for `/commit pr`, `/do pr`, `/fix-issues pr`; pre-existing for
  `/quickfix` at `SKILL.md:637`) → signals "caller skill run completed
  successfully." Dashboard event. Decoupled from PR merge status.

  These three marker families have distinct semantics. The dashboard
  shows one entry per landing event. **A `/quickfix` that completes
  successfully but settles at `pr-ready` (no `--auto`, awaiting human
  merge) DOES produce a `fulfilled.quickfix.<slug>` event (and the user
  sees "/quickfix completed: PR #N ready for review"), but does NOT
  produce a `fulfilled.land-pr.<slug>` event until the human merges.**
  This is the correct activity-feed semantics for #228 Part B.

**D3. No "started" marker for /land-pr.** The wrapper-script architecture
eliminates any need for permit-via-existence at the carve-out point. The
hook makes its decision without consulting `fulfilled.land-pr.*` at all
(D1). This diverges from `/verify-changes`'s write-early-as-permit pattern
(`skills/verify-changes/SKILL.md:239,713`) and is justified by the
architecture: `/verify-changes`'s enforcement target is *commits*, where
no wrapper-script shield exists. **Source-vs-runtime clarification
(DA-1-6):** D3's "future maintainer might inline `gh pr create`"
mitigation is the Phase 4 negative-grep conformance assert against skill
SOURCE drift, NOT a runtime check. Runtime is the hook itself; source-drift
is conformance.

**D4. Hook matches precisely `gh pr create` and `gh pr merge --auto`.**
Other `gh` subcommands are NOT matched: `gh issue create`, `gh run watch`,
`gh pr view`, `gh pr checks`, `gh pr edit`, `gh pr list`, bare `gh pr
merge` (without `--auto`, which is interactive and remains permitted),
`gh pr --help`, `gh --help`. Match is precise tokenize-then-walk via a
new `is_gh_pr_subcommand` helper in `hooks/_lib/git-tokenwalk.sh`, drift-
gated alongside `is_git_subcommand`.

**D5. ID per caller (issue #224 J / #228 AC):**
| Caller         | Tracking-id source                                    | `parent:` in marker |
|----------------|-------------------------------------------------------|----------------------|
| `/commit pr`   | `$BRANCH_SLUG` (already computed for /tmp filenames)  | `commit`             |
| `/do pr`       | `$TASK_SLUG` (also used as PIPELINE_ID basename)      | `do`                 |
| `/quickfix`    | `$SLUG` (also used in `fulfilled.quickfix.$SLUG`)     | `quickfix`           |
| `/fix-issues pr` | `$ISSUE_NUM` (per-issue iteration)                  | `fix-issues`         |

No new sanitization rule needed — each caller's existing variable is
already filename-safe. `sanitize-pipeline-id.sh` continues to apply only
at PIPELINE_ID basename construction, not to `<id>` itself (matches
`/run-plan` SKILL.md:825 pattern).

**D6. PIPELINE_ID & MAIN_ROOT resolution per caller.** Markers are
written to `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/` where `$MAIN_ROOT`
is the caller's natural bookkeeping root (worktree for `/do pr` and
`/fix-issues pr`; main repo for `/commit pr` and `/quickfix`).
`$ZSKILLS_PIPELINE_ID` is exported by the caller before invoking
`/land-pr`. The hook does NOT need to resolve marker locations for gating
(D1 — unconditional deny). The hook DOES read markers for STOP-message
wording; it probes BOTH `$(git rev-parse --git-common-dir)/..` and
`$(git rev-parse --show-toplevel)` paths (defensively), but a missing
or stale marker only degrades STOP-message specificity, not gating
correctness. (R-1-4 risk eliminated: hook gating no longer depends on
marker freshness.)

**D7. Per-skill `fulfilled.<skill>.<id>` writes (revised per DA-1-8).**
Each of `/commit pr`, `/do pr`, `/fix-issues pr` writes
`fulfilled.<skill>.<id>` with `status: started` at skill entry and
finalizes to `status: complete` (or `failed` / `cancelled`) at the end
of the caller-loop via the **explicit-finalize** pattern documented in
Phase 2 (NOT trap-on-EXIT — see DA-2-1 / DA-3-1 lessons).
`/quickfix`'s existing `fulfilled.quickfix.$SLUG` write is preserved.
`/run-plan` already writes `fulfilled.run-plan.<id>` (`SKILL.md:826-829`);
also unchanged.

**Pre-existing `/quickfix` trap bug (DA-3-3 — out of scope).** /quickfix
SKILL.md uses 21+ bash fences; its `trap 'finalize_marker $?' EXIT`
(line 677) fires when the *setting* fence exits — which is `rc=0`
immediately, stamping `status: complete` on entry. The `fulfilled.quickfix.<slug>`
marker's `status` field is therefore unreliable in current /quickfix.
This is a **pre-existing bug surfaced by the review**, NOT introduced
by this plan. It is documented here for posterity; fixing it requires
restructuring /quickfix to either single-fence or explicit-finalize.
File as a separate Wave 1 follow-up; do NOT attempt to fix in this plan
to avoid scope creep. This means #228 Part B's AC for /quickfix
(`fulfilled.quickfix.<slug>` with `status: complete` on success) is
NOT strictly met by current /quickfix; this plan's other callers DO
meet the AC via explicit-finalize.

This satisfies #228 Part B's literal AC for `/commit`, `/do`,
`/fix-issues`, `/run-plan`, `/land-pr`; /quickfix is partial-AC (marker
exists but status field is unreliable per pre-existing bug). The
markers are **independent of and parallel to** `fulfilled.land-pr.<id>`
(which signals merge, not skill-completion).

**D8. STOP-message wording branches on tracking state.** When the hook
denies, it inspects `.zskills/tracking/*/requires.land-pr.*` (in BOTH
MAIN_ROOT and WORKTREE_ROOT) and reads the body's `branch:` field:
- **Pattern 2** (requires.land-pr.* with `branch: <current HEAD>` exists)
  → "Your `/land-pr` invocation appears to have errored mid-flight. The
  recovery is to fix the `/land-pr` args (check the `--result-file` for
  the failure reason and the caller-loop pattern at
  `skills/land-pr/references/caller-loop-pattern.md`), NOT to fall back
  to direct `gh pr create` / `gh pr merge --auto`."
- **Pattern 1** (no matching requires.land-pr.* for current branch)
  → "You're outside a caller skill (or your caller hasn't reached the
  land step). Use one of: `/commit pr` (typed feature branch), `/quickfix
  <description>` (one-off small change), `/do pr <task>` (task PR), or
  `/fix-issues pr` (issue-driven PR). Or dispatch `/land-pr` yourself via
  Skill tool: `Skill { skill: \"land-pr\", args: \"--branch=$(git
  symbolic-ref --short HEAD) --title=... --body-file=... --result-file=...
  --tracking-id=...\" }`."

Both variants append the same final clause: "If you need a true manual
one-off (rare), open a SEPARATE terminal outside the Claude Code session
— the hook only sees Bash *tool* invocations."

STOP-message is ASCII-only (no Unicode bullets/em-dashes per DA-1-11);
conformance grep anchor is `STOP: direct gh pr` (no backtick — DA-1-11).

**D9. Narrow clear-tracking preservation (in-scope subset of Wave 1).**
Phase 3 extends `skills/update-zskills/scripts/clear-tracking.sh` case statement (`:48-57`) by
extending the existing `fulfilled.run-plan.*)` arm to also match the
new families: `fulfilled.land-pr.*`, `fulfilled.commit.*`,
`fulfilled.do.*`, `fulfilled.fix-issues.*`, and `fulfilled.quickfix.*`
(pre-existing but currently wiped against #228 Part B's intent).

**The post-clear residual-count assertion at `:150-157` does NOT need
modification** — verified empirically against the source: it lists
*classes that SHOULD be cleared* (`requires.*`, `step.*`,
`fulfilled.verify-changes.*`, `fulfilled.draft-plan.*`,
`fulfilled.refine-plan.*`, `verify-pending-attempts.*`), and the new
preserved markers are not among them. The "lockstep" concern from
`97c7d19`'s commit message applies when we change which markers are
*cleared*, which this plan doesn't. (R-2-1 verification correction.)

Wave 1 will subsume this with a broader `fulfilled.*.*` rule; this
narrow patch is strictly a subset and lands here to avoid hard cross-
plan ordering coupling. (DA-1-4 resolution.)

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — tokenize-walk helper + hook | ⬚ | | new `is_gh_pr_subcommand` + `block-bypassed-land-pr.sh` |
| 2 — Caller edits (4 skills) | ⬚ | | `requires.land-pr.<id>` + `--tracking-id` + new `fulfilled.<skill>.<id>` |
| 3 — Hook registration + clear-tracking narrow widening | ⬚ | | `.claude/settings.json` + mirror + 6-line clear-tracking patch |
| 4 — Conformance tripwires | ⬚ | | `test-skill-conformance.sh` asserts (positive + negative) + `test-hook-helper-drift.sh` |
| 5 — Hook integration test + canary | ⬚ | | `tests/test-block-bypassed-land-pr.sh` + `docs/plans/CANARY_BYPASS_DETECT.md` |
| 6 — metadata.version bumps + final mirror | ⬚ | | per-skill bumps; final `cp -a` to `.claude/{skills,hooks}` |

## Phase 1 — Tokenize-walk helper + new hook

### Goal

Add `is_gh_pr_subcommand` (and its segment-walking sibling) to the shared
tokenize-walk library; implement `hooks/block-bypassed-land-pr.sh` as a
PreToolUse Bash hook that **unconditionally** denies direct `gh pr
create` and `gh pr merge --auto` from agent Bash invocations, with a
STOP message that branches on tracking-state diagnostics.

### Work Items

- [ ] **Extend `hooks/_lib/git-tokenwalk.sh`** with two new helpers,
  maintained alongside the existing four:
  - `is_gh_pr_subcommand cmd want_sub [flag_regex]` — first-token-anchored.
    Tokenize on whitespace; skip env-var prefixes (`KEY=VAL...`) + optional
    `env`; require literal `gh` next; walk past `gh`-level flags
    (`-R|--repo` consume 2 tokens; `--repo=value` form consumes 1;
    `-h|--help|--version|--no-pager` consume 1 each; any `--foo=bar`
    consumes 1); require next token == `pr`; require next-next token
    == `$want_sub`. If `$flag_regex` is non-empty, require some
    subsequent token to match (flag-order-agnostic — e.g.,
    `gh pr merge --auto --squash` and `gh pr merge --squash --auto`
    both match `is_gh_pr_subcommand cmd merge '^--auto$'`). Set
    `GH_PR_SUB_INDEX` / `GH_PR_SUB_REST` on match.
  - `is_gh_pr_subcommand_in_chain cmd want_sub [flag_regex]` — segment-
    walks chained-form via the same segment-split rules as
    `is_git_subcommand_in_chain` (`&&`, `||`, `;`, `|`, real newline,
    JSON-escaped `\n`).
- [ ] **Inline the helpers** verbatim into `hooks/block-bypassed-land-pr.sh`
  with the standard drift-gate header comment:
  ```
  # Inlined from hooks/_lib/git-tokenwalk.sh (source-of-truth).
  # Drift gate: tests/test-hook-helper-drift.sh.
  ```
- [ ] **Create `hooks/block-bypassed-land-pr.sh`** following
  `block-stale-skill-version.sh:1-163` shape:
  - `set -u`
  - Read stdin (JSON envelope).
  - Filter non-Bash tool invocations (early `exit 0`, matches
    `block-stale-skill-version.sh:46-48`).
  - Extract `"command"` via the canonical sed pattern from
    `block-unsafe-generic.sh:37` (with the `$INPUT` fallback for
    defensive scanning).
  - **Bash-only early-exit short-circuit (DA-1-9):**
    ```bash
    case "$COMMAND" in
      *"gh pr "*) ;;  # fall through to tokenize-walk
      *) exit 0 ;;
    esac
    ```
  - Match via inlined helpers:
    ```bash
    is_gh_pr_subcommand_in_chain "$COMMAND" "create" && deny=1
    is_gh_pr_subcommand_in_chain "$COMMAND" "merge" '^--auto$' && deny=1
    [ "${deny:-0}" -eq 0 ] && exit 0
    ```
  - On match: invoke `scripts/land-pr-bypass-message.sh` to read tracking
    state and emit the appropriate STOP message string to stderr; capture
    stderr.
  - Emit deny envelope via inlined pure-bash `json_escape` (verbatim from
    `block-stale-skill-version.sh:132-159` — `LC_ALL=C`, `[[:cntrl:]]`
    strip, NOT the broken bash range form).
  - **Defensive: empty stderr from script triggers static fallback**
    (DA-3-6 fix). If the message-script exited but `$STDERR` is empty
    OR shorter than 50 chars, use the static fallback STOP message
    text below instead of the captured stderr. Rationale: a bug in the
    message script (returns rc=1 but no stderr) would otherwise produce
    a deny envelope with empty `permissionDecisionReason`, leaving the
    agent with no diagnostics.
  - **Fail-open scope** if `scripts/land-pr-bypass-message.sh` is missing
    or not executable: `[ -x "$SCRIPT" ] || USE_STATIC_FALLBACK=1`. The
    hook STILL DENIES the match — it just falls back to a static
    minimal STOP message. The fail-open is on the *message-enrichment*
    script, not on the *deny decision*. This is a deliberate divergence
    from `block-stale-skill-version.sh:126` (which fails-open on missing
    script meaning allow): here, the deny decision is unconditional;
    only the message enrichment is conditional.
  - Static fallback STOP message: ASCII-only, 3 lines:
    ```
    STOP: direct gh pr (create|merge --auto) from agent Bash bypasses /land-pr.
    Use /commit pr / /quickfix / /do pr / /fix-issues pr, or dispatch Skill { skill: "land-pr" }.
    Open a SEPARATE terminal for legitimate one-off manual operations.
    ```
- [ ] **Create `scripts/land-pr-bypass-message.sh`**:
  - Read current branch: `HEAD=$(git symbolic-ref --short HEAD 2>/dev/null)`
    — recovery-to-empty allowed (`2>/dev/null` documented exception
    per `/land-pr` SKILL.md:250-252 precedent). If HEAD is empty
    (detached HEAD or non-repo cwd), skip the branch-match scan and
    fall straight to Pattern 1 fallback (R-2-7).
  - Resolve MAIN_ROOT: `git rev-parse --git-common-dir/..`; resolve
    WORKTREE_ROOT: `git rev-parse --show-toplevel`.
  - Scan `{MAIN_ROOT,WORKTREE_ROOT}/.zskills/tracking/*/requires.land-pr.*`
    for a marker whose body contains `^branch: $HEAD$`. **Backward-compat
    fallback (DA-2-2):** if the marker exists but has NO `branch:` line
    at all (legacy marker shape from before this plan, e.g.,
    pre-modification `/run-plan`-written markers), treat it as a match
    — emit Pattern 2. Reason: missing-branch-field means "we know a
    caller is mid-flight in this pipeline but the marker is too old to
    branch-correlate"; Pattern 2's wording is the safer default for
    that ambiguity.
  - If a branch-match found OR a missing-branch-field marker exists
    → emit the **Pattern 2** STOP message (see D8) to stderr; exit 1.
  - Else → emit the **Pattern 1** STOP message to stderr; exit 1.
  - Both STOP messages are ASCII-only (no Unicode bullets / em-dashes);
    use `- ` for list items.
- [ ] **STOP-message body fragments** (locked verbatim for conformance
  anchoring — DA-1-11):
  - Pattern 1 unique anchor substring: `STOP: direct gh pr` and
    `outside a caller skill`.
  - Pattern 2 unique anchor substring: `STOP: direct gh pr` and
    `/land-pr invocation appears to have errored`.
  - Both end with: `If you need a true manual one-off, open a SEPARATE
    terminal outside the Claude Code session.`

### Design & Constraints

- **Bash-only hook source** (no external interpreters; C6).
- **No `jq`** binary (C3).
- **No `|| true`**; `2>/dev/null` only on `git rev-parse` probes whose
  recovery-to-empty is explicitly handled (matches `/land-pr` SKILL.md
  documented exception).
- **Pure-bash JSON-escape** via verbatim `json_escape` from
  `block-stale-skill-version.sh:132-159`.
- **Fail-open scope** is narrowed to message-enrichment, NOT deny
  decision (see Work Items above).
- **Drift-gate the inlined helpers** via Phase 4.
- **Branch-binding via `branch:` field** in marker body. `/land-pr` already
  writes the `branch:` field in the worktree-side `.landed` marker
  (`SKILL.md:498-499`); Phase 1 also modifies the printf at
  `SKILL.md:533` to include `branch: $BRANCH` in the central
  `fulfilled.land-pr.<id>` marker body. The edit changes the format
  string (`'skill:\nid:\npr:\ndate:\n'` → `'skill:\nid:\npr:\nbranch:\ndate:\n'`)
  and adds `"$BRANCH"` to the printf args — modifies two physical lines
  but is a single logical change (R-2-2 / DA correction). Triggers
  `/land-pr` `metadata.version` bump in Phase 6.
  The new `requires.land-pr.<id>` writes in Phase 2 also include
  `branch:` field for the same lookup pattern. **Backward-compat:**
  pre-existing `fulfilled.land-pr.*` markers from before this plan
  landed have no `branch:` field; the hook's STOP-message script must
  treat missing-branch-field as "Pattern 2 fallback" (mid-flight,
  branch unknown) rather than "no match" (R-2-2 detached-HEAD parallel).
- **Wrapper-script carve-out is automatic** — `/land-pr`'s own `gh pr
  create` is inside `pr-push-and-create.sh:142`; the hook never sees it
  because Bash tool calls reaching this hook are `bash $script_path`,
  not the inner `gh` invocation. Documented in the hook header comment.

### Acceptance Criteria

- [ ] AC1.1: `hooks/_lib/git-tokenwalk.sh` exports `is_gh_pr_subcommand`
  and `is_gh_pr_subcommand_in_chain`. Sourcing the lib then calling
  `is_gh_pr_subcommand "gh pr create -B main" create && echo MATCH` →
  `MATCH`.
- [ ] AC1.2: `hooks/block-bypassed-land-pr.sh` exists, is executable,
  and on stdin `{"tool_name":"Bash","tool_input":{"command":"gh pr create -B main"}}`
  with NO requires.land-pr.* present anywhere → deny envelope whose
  `permissionDecisionReason` contains both `STOP: direct gh pr` and
  `outside a caller skill`.
- [ ] AC1.3: Same hook, stdin same, but with
  `$MAIN_ROOT/.zskills/tracking/quickfix.foo/requires.land-pr.foo`
  containing `branch: <current HEAD>` → deny envelope contains
  `STOP: direct gh pr` and `/land-pr invocation appears to have errored`
  (Pattern 2 wording).
- [ ] AC1.4: Hook on stdin
  `{"command":"gh issue create -t foo"}` → empty stdout + exit 0 (allow;
  non-`pr` verb).
- [ ] AC1.5: Hook on `{"command":"cd /tmp/wt && gh pr create -B main"}`
  → deny envelope (segment-walk).
- [ ] AC1.6: Hook **still denies** when `scripts/land-pr-bypass-message.sh`
  is removed; emits the static fallback STOP message via its inlined
  json_escape. (Differs from block-stale-skill-version.sh's "fail-open
  means allow" — see D&C above.)
- [ ] AC1.7: Hook matches all 4 flag-order permutations of merge+auto:
  `gh pr merge --auto`, `gh pr merge --auto --squash`,
  `gh pr merge --squash --auto`, `gh pr merge --merge --auto`. All deny.
- [ ] AC1.8: Hook does NOT match bare `gh pr merge` (no `--auto`) — exit 0.
- [ ] AC1.9: Hook does NOT match `gh -R foo/bar pr view 123`, `gh pr
  --help`, `gh --help`, `gh pr checks --watch` — all exit 0.
- [ ] AC1.10: Bash-only early-exit short-circuit fires for commands not
  containing `"gh pr "` substring (verify by tracing that
  `land-pr-bypass-message.sh` is NOT invoked for `ls`, `cat`, `git
  commit`, etc.). Test via instrumented stub script that exits 99 on
  invocation; the hook should exit 0 without ever invoking it.
- [ ] AC1.11: `--repo=foo/bar` (`=`-form, 1 token) and `--repo foo/bar`
  (2-token form) both correctly walked past — `gh --repo=foo/bar pr
  create` and `gh --repo foo/bar pr create` both match and deny.

### Dependencies

None. This phase is implementable and verifiable in isolation.

### Commit boundary

One commit at end of phase: `feat(hook): block-bypassed-land-pr.sh + is_gh_pr_subcommand helper`.
Includes:
- `hooks/_lib/git-tokenwalk.sh` (extended with 2 new helpers)
- `hooks/block-bypassed-land-pr.sh` (new)
- `scripts/land-pr-bypass-message.sh` (new)
- `skills/land-pr/SKILL.md:533` (1-line edit: add `branch: $BRANCH` to
  fulfilled marker write); `metadata.version` bump on /land-pr is
  deferred to Phase 6's batched bump.

## Phase 2 — Caller skill edits (4 skills)

### Goal

Extend the `requires.land-pr.<id>` + `--tracking-id` pattern across the
four non-`/run-plan` callers. Each caller writes:
1. `requires.land-pr.<id>` (with `branch: $BRANCH` field) before invoking
   `/land-pr`, on a `trap`-on-EXIT cleanup so failed land attempts leave
   no orphan markers.
2. `fulfilled.<skill>.<id>` with `status: started` at skill entry,
   finalized via `trap`-on-EXIT (mirrors `/quickfix`'s existing pattern).
3. `--tracking-id=<id>` in `LAND_ARGS`.

### Work Items

**Marker-lifecycle pattern (all callers).** SKILL.md bash fences run as
separate Bash tool invocations (separate shell sessions); `trap` set in
one fence does NOT persist to the next. So this plan uses the
**explicit-finalize** pattern, NOT `trap`-on-EXIT:

- At the **tracking-setup point** (just before LAND_ARGS), write
  `fulfilled.<skill>.<id> status: started` and `requires.land-pr.<id>`
  (both with `branch:` field).
- **Track `$LAND_OUTCOME` at TWO points inside the caller-loop**
  (R-3-2 / DA-3-2 — STATUS arms and CI_STATUS settle arms are separate):
  - In the outer `case "$STATUS"` block, on failure-class breaks
    (rebase-conflict, push-failed, create-failed, monitor-failed,
    merge-failed, rebase-failed): `LAND_OUTCOME=$STATUS`.
  - In the inner `case "$CI_STATUS"` block (reached only when
    `STATUS ∈ {created, monitored, merged}`): set LAND_OUTCOME based
    on the settle:
    - `pass|none|skipped` and PR_STATE=MERGED → `LAND_OUTCOME=merged`
    - `pass|none|skipped` and PR_STATE=OPEN → `LAND_OUTCOME=pr-ready`
    - `pending` → `LAND_OUTCOME=pr-ready`
    - `not-monitored` → `LAND_OUTCOME=created`
    - `fail` after fix-cycle exhaustion → `LAND_OUTCOME=pr-ci-failing`
  - **Default initialization** at top of caller-loop:
    `LAND_OUTCOME=unknown`. If the loop exits with LAND_OUTCOME still
    `unknown`, treat as failed-class.
- After the caller-loop completes (last bash fence of the skill's
  procedure), apply the explicit-finalize:
  - `FINAL=complete` if `$LAND_OUTCOME ∈ {merged, created, monitored, pr-ready}`
  - `FINAL=failed` if `$LAND_OUTCOME ∈ {rebase-conflict, push-failed,
    create-failed, merge-failed, monitor-failed, rebase-failed,
    pr-ci-failing, unknown}`
  - `FINAL=cancelled` if `$CANCELLED -eq 1`
  - `sed -i "s/^status: started$/status: $FINAL/"` on the fulfilled
    marker.
- ALWAYS remove `requires.land-pr.<id>` at this final step (regardless
  of outcome — transient diagnostic).

**Defensive `exit 1` paths (DA-3-1):** Each caller has defensive
`exit 1` paths (e.g., `skills/commit/modes/pr.md:96` when RESULT_FILE
is missing). These bypass the explicit-finalize. Acceptance criterion:
each `exit 1` path MUST be preceded by an inline call to the same
cleanup logic (or a small helper function that is sourced into each
relevant bash fence — note: function-source pattern works because the
function body is re-defined per fence, not preserved). The plan adds
the cleanup inline before each defensive `exit 1` for simplicity.

DA-2-1 verification confirms `break` in the caller-loop returns rc=0
universally, so the previous trap-`$?` design was incorrect. The
explicit-finalize with two-point LAND_OUTCOME tracking sidesteps both
lifecycle and rc semantics.

- [ ] **`/commit pr`** — `skills/commit/modes/pr.md`:
  - Insert a tracking-setup block before LAND_ARGS assembly (currently
    line ~77):
    ```bash
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    PIPELINE_ID="commit.$BRANCH_SLUG"
    export ZSKILLS_PIPELINE_ID="$PIPELINE_ID"
    TRACK_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
    mkdir -p "$TRACK_DIR"
    NOW_ISO=$(TZ="${TIMEZONE:-UTC}" date -Iseconds)
    HEAD_BRANCH=$(git symbolic-ref --short HEAD)
    # fulfilled.<skill>.<id> start-marker (per #228 Part B).
    cat > "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG" <<MARK
    status: started
    date: $NOW_ISO
    skill: commit
    mode: pr
    branch: $HEAD_BRANCH
    MARK
    # requires.land-pr.<id> (drives hook STOP-message Pattern 2 + dashboard).
    cat > "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG" <<MARK
    skill: land-pr
    parent: commit
    id: $BRANCH_SLUG
    branch: $HEAD_BRANCH
    date: $NOW_ISO
    MARK
    ```
  - Inside the caller-loop's `case "$STATUS"` arms (around line ~125),
    set `LAND_OUTCOME=$STATUS` before each `break` (the case already
    knows the outcome; we just need to surface it for the explicit
    finalize step).
  - After the caller-loop closes (`# === END CANONICAL /land-pr CALLER LOOP ===`,
    line ~213), append a finalize block:
    ```bash
    case "$LAND_OUTCOME" in
      merged|created|monitored|pr-ready) FINAL=complete ;;
      cancelled) FINAL=cancelled ;;
      *) FINAL=failed ;;
    esac
    sed -i "s/^status: started$/status: $FINAL/" "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG"
    rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
    ```
  - Append `--tracking-id=$BRANCH_SLUG` to `LAND_ARGS` at line ~77.

- [ ] **`/do pr`** — `skills/do/modes/pr.md`:
  - `$MAIN_ROOT` (line ~67) and `$TASK_SLUG` (line ~62) already in scope.
  - PIPELINE_ID already constructed as `do.$TASK_SLUG`.
  - Add tracking-setup block (same shape as `/commit pr`) BEFORE LAND_ARGS
    at line ~190: writes `fulfilled.do.$TASK_SLUG status: started` +
    `requires.land-pr.$TASK_SLUG` (both with `branch:`).
  - Track `LAND_OUTCOME` inside the caller-loop case arms.
  - After caller-loop closes, append the explicit-finalize block (same
    case statement; `sed -i` rewrites `fulfilled.do.$TASK_SLUG`; remove
    `requires.land-pr.$TASK_SLUG`).
  - Append `--tracking-id=$TASK_SLUG` to `LAND_ARGS`.

- [ ] **`/quickfix`** — `skills/quickfix/SKILL.md`:
  - The existing `fulfilled.quickfix.$SLUG` write at line 637 is
    PRESERVED unchanged (regression-asserted in Phase 4).
  - The existing `finalize_marker` trap at lines 653-677 is PRESERVED
    unchanged (it was the design baseline; we are not propagating its
    trap pattern to other callers, but `/quickfix`'s existing flow may
    work for it specifically per its single-fence structure — we do
    NOT modify `/quickfix`'s lifecycle plumbing).
  - Insert `requires.land-pr.$SLUG` write IMMEDIATELY AFTER the existing
    fulfilled.quickfix write block (after line ~650), with `branch:
    $BRANCH` field.
  - At the **end of the caller-loop** in `/quickfix` (around line 1244,
    after `# === END CANONICAL /land-pr CALLER LOOP ===`), append a
    one-line cleanup: `rm -f "$TRACK_DIR/requires.land-pr.$SLUG"` (the
    fulfilled.quickfix finalize is already handled by /quickfix's
    existing trap; this just cleans up the new requires marker so it
    doesn't orphan).
  - Append `--tracking-id=$SLUG` to `LAND_ARGS` at line ~1080.

- [ ] **`/fix-issues pr`** — `skills/fix-issues/modes/pr.md`:
  - `$MAIN_ROOT`, `$PIPELINE_ID`, `$ISSUE_NUM` already in scope.
  - **Sprint-level** `fulfilled.fix-issues.$SPRINT_ID` with
    `status: started` written ONCE at sprint start (top of pr.md flow);
    finalized at sprint end (after all issues complete) via explicit
    `sed -i` rewrite based on a sprint-level `$SPRINT_OUTCOME` variable.
  - **Per-issue** `requires.land-pr.$ISSUE_NUM` with `branch: $BRANCH`
    written before each iteration's LAND_ARGS assembly at line ~88.
  - **Per-issue** explicit-finalize: after each per-issue caller-loop
    closes, `rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$ISSUE_NUM"`.
    The per-issue land outcome contributes to sprint-level
    `$SPRINT_OUTCOME` (e.g., any per-issue `failed` → sprint `failed`;
    all `complete` → sprint `complete`).
  - Append `--tracking-id=$ISSUE_NUM` to per-issue `LAND_ARGS`.

- [ ] **`/run-plan` SKILL.md:851-855 — add `branch:` field (DA-2-2 +
  R-3-1 fix).** Modify the existing `requires.land-pr.<id>` write to
  include the branch field. Verified empirically: current shape is
  `printf 'skill: land-pr\nparent: run-plan\nid: %s\ndate: %s\n'`;
  modify to `printf 'skill: land-pr\nparent: run-plan\nid: %s\nbranch: %s\ndate: %s\n'`
  with `"$(git symbolic-ref --short HEAD)"` as the new arg. (R-3-1
  verified: `$BRANCH_NAME` is defined at line 1212, well AFTER line 851
  — out of scope. Use inline `git symbolic-ref` instead.)
- [ ] **`/run-plan` modes/pr.md caller-loop — add explicit-finalize
  for `requires.land-pr.<id>` (DA-3-4 fix).** /run-plan's caller-loop
  ends at `skills/run-plan/modes/pr.md:536` without removing the
  requires marker. Add at line 537+ (after `# === END CANONICAL ... ===`):
  ```bash
  # Cleanup transient requires marker (explicit-finalize per
  # docs/plans/LAND_PR_BYPASS_HARDENING.md D2/D8).
  rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$TRACKING_ID"
  ```
  /run-plan does NOT need a `fulfilled.run-plan.<id>` finalize because
  it ALREADY writes `fulfilled.run-plan.<id> status: started` at Phase
  1 step 8 (SKILL.md:826-829) and is presumed complete at end of
  run-plan flow — that lifecycle is pre-existing and out of scope.

- [ ] **`/land-pr` SKILL.md:533 — modify printf to add `branch:` field**
  (specified in Phase 1 D&C). Format-string change + one new printf
  arg.

- [ ] **PIPELINE_ID export discipline.** Every caller exports
  `ZSKILLS_PIPELINE_ID` BEFORE invoking `/land-pr` via the Skill tool.
  `/land-pr` Step 8b at `SKILL.md:529` already reads it. Pre-existing
  contract; ensure all 5 callers honor it.

### Design & Constraints

- **Marker shape mirrors `/run-plan` SKILL.md:851-855** exactly:
  `skill: land-pr\nparent: <caller>\nid: %s\nbranch: %s\ndate: %s\n`.
  The new `branch:` field is the additional element this plan introduces.
- **`/commit pr` and `/quickfix` do not pass `--auto`** to /land-pr per
  their existing contracts (human review required). Their requires
  markers will exist; fulfilled.land-pr.<id> will be written only if
  the human later merges via a path that re-invokes /land-pr's merge
  step OR they wait for a future re-run. The per-skill fulfilled
  markers (`fulfilled.commit.<id>`, `fulfilled.quickfix.<id>`) ARE
  written on skill-completion regardless of merge status — these are
  the dashboard's signal for "/commit pr completed successfully."
- **`/do pr` and `/fix-issues pr` accept `--auto`** and will produce
  matching `fulfilled.land-pr.<id>` when used in auto mode (the common
  end-to-end-automation path) AND `fulfilled.do.<slug>` / `fulfilled.fix-issues.<sprint>`
  for skill-completion.
- **Marker write timing is just-before-dispatch** (DA-1-12 reworded):
  late writes are sufficient because the bypass surface (`gh pr
  (create|merge --auto)`) only exists at or after the dispatch site.
  Writing requires earlier offers no additional protection and risks
  orphaned markers on early-error paths. The trap-on-EXIT cleanup is
  the additional safety belt for the dispatch-site write path itself.
- **No backwards-compatibility shim** (memory:
  feedback_no_premature_backcompat).
- **PR-mode bookkeeping rule (C10) honored** per D6: each caller writes
  markers to its natural bookkeeping root.

### Acceptance Criteria

- [ ] AC2.1: Manually exercising the modified `/commit pr` block writes
  `requires.land-pr.$BRANCH_SLUG` (with `branch:` field) to
  `$MAIN_ROOT/.zskills/tracking/commit.$BRANCH_SLUG/` and writes
  `fulfilled.commit.$BRANCH_SLUG status: started`; `LAND_ARGS` contains
  `--tracking-id=$BRANCH_SLUG`.
- [ ] AC2.2: Same for `/do pr`: `requires.land-pr.$TASK_SLUG` and
  `fulfilled.do.$TASK_SLUG`; `LAND_ARGS` includes `--tracking-id=$TASK_SLUG`.
- [ ] AC2.3: Same for `/quickfix`: `requires.land-pr.$SLUG` written;
  EXISTING `fulfilled.quickfix.$SLUG` unchanged (regression check).
- [ ] AC2.4: Same for `/fix-issues pr` per-issue:
  `requires.land-pr.$ISSUE_NUM`; sprint-level
  `fulfilled.fix-issues.$SPRINT_ID`.
- [ ] AC2.5: After the caller-loop's `# === END CANONICAL ... ===`
  marker, the explicit-finalize block removes `requires.land-pr.<id>`
  in `/commit pr`, `/do pr`, `/quickfix`, AND per-issue in
  `/fix-issues pr` — regardless of LAND_OUTCOME (verified by simulating
  each STATUS arm: merged, pr-ready, rebase-conflict).
- [ ] AC2.6: Explicit-finalize block in each new caller (commit, do,
  fix-issues) rewrites `fulfilled.<skill>.<id>` to:
  - `status: complete` when LAND_OUTCOME ∈ {merged, created, monitored, pr-ready}
  - `status: failed` when LAND_OUTCOME ∈ {rebase-conflict, push-failed, create-failed, merge-failed, monitor-failed, rebase-failed}
  - `status: cancelled` when CANCELLED=1.
- [ ] AC2.7: End-to-end `/do pr` auto-mode invocation produces:
  `fulfilled.do.$SLUG status: complete` + `fulfilled.land-pr.$SLUG
  status: complete` (via /land-pr Step 8b on row-6 merge).
- [ ] AC2.8 (regression): `/quickfix`'s pre-existing
  `fulfilled.quickfix.$SLUG` shape (status fields, finalize_marker
  behavior) is byte-identical pre- and post-this-plan.
- [ ] AC2.9 (DA-2-2): `/run-plan`'s `requires.land-pr.<id>` write at
  `SKILL.md:851-855` now includes `branch: <branch_name>` field.
  Verified by reading the file post-edit.
- [ ] AC2.10: Synthesizing a failure mid-caller-loop (e.g., STATUS=push-failed
  break path) followed by explicit-finalize → `fulfilled.<skill>.<id>`
  ends as `status: failed`, NOT `complete` (DA-2-1 fix verification).

### Dependencies

Phase 1 may merge before Phase 2 (independent). Phase 2 verifiable in
isolation (markers + LAND_ARGS shape).

### Commit boundary

One commit: `feat(skills): caller tracker parity — requires.land-pr + per-skill fulfilled (4 callers)`.

## Phase 3 — Hook registration + clear-tracking narrow widening + mirror

### Goal

Register the new hook in `.claude/settings.json`, mirror source files to
the install layout, and apply the **narrow** `clear-tracking.sh`
preservation patch (D9) so the markers introduced by this plan survive
clear-tracking until Wave 1 lands its broader widening.

### Work Items

- [ ] **Edit `.claude/settings.json`**: append a new entry to the
  `PreToolUse` Bash matcher's `hooks` array:
  ```json
  {
    "type": "command",
    "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/block-bypassed-land-pr.sh"
  }
  ```
  Place AFTER `block-stale-skill-version.sh`. (Order is cosmetic per
  R-1-7 — PreToolUse hooks compose additively; we use diff-readability
  rather than semantic ordering.)
- [ ] **Mirror to `.claude/hooks/`**: `cp -a hooks/block-bypassed-land-pr.sh
  .claude/hooks/`. Verify executable bit set.
- [ ] **Source-tree `scripts/land-pr-bypass-message.sh`** lives at the
  source path; no `.claude/scripts/` mirror needed (per domain agent §A
  — `block-stale-skill-version.sh` resolves `$SCRIPT` via
  `${CLAUDE_PROJECT_DIR:-$PWD}/scripts/...`, so source-tree `scripts/`
  is the live path).
- [ ] **Update `skills/update-zskills/SKILL.md`** install-triples table
  (per codebase agent §C, lines 1149-1156): add the new hook entry.
  Triggers a `metadata.version` bump on `/update-zskills` (Phase 6).
- [ ] **Narrow `clear-tracking.sh` preservation patch (D9):**
  - Edit `skills/update-zskills/scripts/clear-tracking.sh:48-57` case statement:
    ```bash
    case "$base" in
      fulfilled.run-plan.*|fulfilled.land-pr.*|fulfilled.commit.*|fulfilled.do.*|fulfilled.fix-issues.*|fulfilled.quickfix.*)
        preserve_count=$((preserve_count+1)) ;;
      requires.*)
        c_requires=$((c_requires+1)) ;;
      step.*|phasestep.*)
        c_step=$((c_step+1)) ;;
      verify-pending-attempts.*)
        c_vpa=$((c_vpa+1)) ;;
      fulfilled.verify-changes.*|fulfilled.draft-plan.*|fulfilled.refine-plan.*)
        # Wave 1 (issue #228 Part A) will widen; preserved here as bookkeeping for now.
        c_other=$((c_other+1)) ;;
      *)
        c_other=$((c_other+1)) ;;
    esac
    ```
  - Edit the residual-count assertion at lines 150-157: remove
    `fulfilled.land-pr.*`, `fulfilled.commit.*`, `fulfilled.do.*`,
    `fulfilled.fix-issues.*`, `fulfilled.quickfix.*` from the
    residual-class enumeration (they are now preserved, so they MUST
    not trip the assert).
  - Mirror via `bash scripts/mirror-skill.sh update-zskills` (since
    clear-tracking lives in update-zskills's `scripts/` subdir per
    codebase agent §A).
- [ ] **/update-zskills consumer-customization note (DA-1-10):** Phase 3
  does NOT add a merge-style installer for `.claude/settings.json`. The
  existing `/update-zskills` Step C install behavior governs. If
  consumers have customized `.claude/settings.json`, they may lose
  customizations on next install. Document this as a known limitation
  in `skills/update-zskills/SKILL.md` IF the existing docs are silent
  on it (verify via grep first). If already documented, no edit needed.

### Design & Constraints

- **Manual `cp -a` mirror** (codebase agent §E confirms no
  `scripts/mirror-hook.sh` exists).
- **Settings.json registration position is cosmetic** (R-1-7 — additive
  composition).
- **Clear-tracking widening is NARROW**: only the marker families this
  plan introduces (plus pre-existing `fulfilled.quickfix.*` which was
  previously wiped against #228 Part B's intent). Wave 1's broader
  `fulfilled.*.*` widening is a strict superset and will land later;
  this narrow patch is a forward-compatible subset.
- **Residual assertion is updated in lockstep** (commit `97c7d19`
  message: "silent drift becomes loud failure"). Failing this in lockstep
  would cause clear-tracking to fail on every run.

### Acceptance Criteria

- [ ] AC3.1: `.claude/settings.json` has 4 PreToolUse Bash hook entries
  after this phase (was 3).
- [ ] AC3.2: `ls -la .claude/hooks/block-bypassed-land-pr.sh` shows the
  file present, executable.
- [ ] AC3.3: Live smoke test in a fresh session: `gh pr create` as a
  Bash tool call → hook fires with the Pattern 1 STOP message
  (assuming no requires marker matching current branch).
- [ ] AC3.4: `bash skills/update-zskills/scripts/clear-tracking.sh` after a synthesized
  session that wrote `fulfilled.land-pr.foo` + `fulfilled.commit.bar`
  + `fulfilled.draft-plan.baz` preserves the first two and clears the
  third (the third is Wave 1's responsibility).
- [ ] AC3.5: `bash skills/update-zskills/scripts/clear-tracking.sh` residual assertion
  (lines 150-157) returns 0 (no residual; lockstep with new preservation).
- [ ] AC3.6: Mirror diff: `diff hooks/block-bypassed-land-pr.sh
  .claude/hooks/block-bypassed-land-pr.sh` returns empty.
- [ ] AC3.7: `/update-zskills` (dry-run) reports the new hook in its
  install manifest.

### Dependencies

Phase 1 (hook source must exist).

### Commit boundary

One commit: `chore(hooks): register block-bypassed-land-pr.sh + narrow clear-tracking preservation + mirror`.

## Phase 4 — Conformance tripwires

### Goal

Lock the structural defense into the existing conformance test suite —
positive asserts that the new caller code is present, AND **negative
asserts** that no skill source contains a bypass pattern (DA-1-5).

### Work Items

- [ ] **`tests/test-skill-conformance.sh`** — add cross-skill asserts at
  the existing extension region (patterns agent §C, around line 468 —
  `cross_check_no_invocation` helper neighborhood):

  Positive asserts (R-1-9 + R-1-11; R-3-3 corrected: explicit-finalize,
  NOT trap):
  - Each of the 4 caller files
    (`skills/commit/modes/pr.md`, `skills/do/modes/pr.md`,
    `skills/quickfix/SKILL.md`, `skills/fix-issues/modes/pr.md`) contains
    the literal substring `--tracking-id=` somewhere between the
    canonical caller-loop start anchor (`# === BEGIN CANONICAL /land-pr
    CALLER LOOP ===`) and end anchor (`# === END CANONICAL /land-pr
    CALLER LOOP ===`).
  - Each caller file contains a `requires.land-pr.` marker-write block
    BEFORE the `LAND_ARGS=` line (textual-precedence assert — R-1-3).
  - Each new caller (commit, do, fix-issues — NOT quickfix) contains
    BOTH (a) a `fulfilled.<skill>.` start-marker write block AND (b)
    an `explicit-finalize` block AFTER the `# === END CANONICAL ... ===`
    anchor that contains a `sed -i "s/^status: started$/status:` line
    (the rewrite) AND an `rm -f .*requires.land-pr.` line (the cleanup).
  - `/quickfix`'s pre-existing `fulfilled.quickfix.$SLUG` write at
    `SKILL.md:637` is unchanged (byte-anchor on the surrounding lines).
  - `/quickfix` contains an `rm -f .*requires.land-pr.` line AFTER the
    `# === END CANONICAL ... ===` anchor (the new requires-cleanup).
  - `/run-plan modes/pr.md` contains an `rm -f .*requires.land-pr.`
    line AFTER its `# === END CANONICAL ... ===` anchor (DA-3-4 fix).
  - `/run-plan SKILL.md` line 851-855 write block contains `branch:`
    in its printf format string (DA-2-2 + R-3-1).
  - `.claude/settings.json` contains the new hook entry.
  - `hooks/block-bypassed-land-pr.sh` is executable AND contains the
    inlined `is_gh_pr_subcommand` function header line.
  - `scripts/land-pr-bypass-message.sh` contains the ASCII anchor
    `STOP: direct gh pr` AND the Pattern 1 anchor `outside a caller
    skill` AND the Pattern 2 anchor `/land-pr invocation appears to have
    errored`.

  Negative asserts (DA-1-5 + DA-1-6 + R-2-5 + R-3-4):
  - `grep -nE "^[[:space:]]*[^#[:space:]\`].*[^\`]gh pr create[^\`]" skills/land-pr/SKILL.md`
    returns zero matches — anchors exclude lines starting with `\``
    (prose mentioning `\`gh pr create\``) AND require non-backtick
    chars immediately around `gh pr create` (so backtick-wrapped prose
    matches are excluded). **R-3-4 verified false-positive at line 601**
    (` `gh pr create` again. The script does NOT call \`gh pr edit\``)
    is now excluded by this regex. Pre-verify against current source
    before adding the assert — any non-prose match would be a regression.
  - `grep -nrE "(bash|sh)[[:space:]]+-c[[:space:]]*['\"][^'\"]*gh pr (create|merge[^'\"]*--auto)" skills/`
    returns zero matches across ALL skills (no `bash -c '...gh pr...'`
    or `sh -c '...gh pr...'` bypass idiom).
  - `grep -nrE "eval[[:space:]]+['\"][^'\"]*gh pr (create|merge[^'\"]*--auto)" skills/`
    returns zero matches (no `eval 'gh pr create'` bypass idiom).
  - **Verified against current source:** these patterns return zero
    matches today; verify before adding the assert (so the assert
    doesn't immediately fail on a pre-existing legitimate use).
  - If a skill genuinely needs to wrap a gh pr call, it MUST use the
    supporting-script architecture (a separate `.sh` file referenced by
    SKILL.md, NOT a `bash -c` / `eval` inline).

- [ ] **`tests/test-hook-helper-drift.sh`** — extend the `HOOK` enumeration
  with `block-bypassed-land-pr.sh` (4th entry) and add helper-function
  entries for `is_gh_pr_subcommand` + `is_gh_pr_subcommand_in_chain`.
  Byte-diff (`diff`) the inlined body against
  `hooks/_lib/git-tokenwalk.sh`.
- [ ] **`tests/test-hooks.sh`** (if exists with stdin-fixture coverage):
  extend with stdin envelopes exercising AC1.1-1.11 from Phase 1.

### Design & Constraints

- **Conformance asserts grep skill SOURCE**, not runtime behavior
  (DA-1-6 clarification): they catch source-drift regressions that
  would re-open the bypass surface. Runtime bypasses are caught by the
  hook itself, not by conformance.
- **STOP-message wording is locked at the ASCII-only anchor** (`STOP:
  direct gh pr`, etc. — DA-1-11). No backticks, no Unicode.
- **Byte-equality drift gate** matches the existing 4-hook drift gate
  pattern.

### Acceptance Criteria

- [ ] AC4.1: `bash tests/test-skill-conformance.sh` passes with all new
  positive AND negative asserts.
- [ ] AC4.2: `bash tests/test-hook-helper-drift.sh` passes with the 4th
  hook + 2 new helper bodies inline-matching the lib.
- [ ] AC4.3: Removing `--tracking-id=` from any caller's LAND_ARGS →
  conformance FAILS on that specific assert (negative test).
- [ ] AC4.4: Editing `hooks/_lib/git-tokenwalk.sh`'s `is_gh_pr_subcommand`
  body without updating the inlined copy → drift-gate FAILS (negative test).
- [ ] AC4.5: Adding a `bash -c 'gh pr create'` snippet to any skill
  source → conformance negative-assert FAILS (negative test).
- [ ] AC4.6: Adding an inline `gh pr create` to `skills/land-pr/SKILL.md`
  bash fence → conformance negative-assert FAILS (negative test).

### Dependencies

Phase 1 (hook + helper exist) AND Phase 2 (caller edits exist) AND
Phase 3 (settings.json registration).

### Commit boundary

One commit: `test(conformance): lock bypass-hardening — positive + negative asserts`.

## Phase 5 — Hook integration test + canary plan

### Goal

End-to-end integration test (`tests/test-block-bypassed-land-pr.sh`) and
a canary plan (`docs/plans/CANARY_BYPASS_DETECT.md`) exercising the
bypass-detect path under live `/run-plan` execution.

### Work Items

- [ ] **`tests/test-block-bypassed-land-pr.sh`** — follow
  `tests/test-block-stale-skill-version.sh` shape (sandbox-stub
  pattern). Test matrix (16 cases):
  - **C1**: `gh pr create -B main`, no markers → deny, Pattern 1
    STOP message (`outside a caller skill` substring).
  - **C2**: `gh pr create -B main`, `requires.land-pr.foo` with
    `branch: <current HEAD>` present → deny, Pattern 2 STOP
    (`/land-pr invocation appears to have errored` substring).
  - **C3**: `gh pr create -B main`, `requires.land-pr.foo` with
    `branch: someOtherBranch` (NOT current HEAD) → deny, Pattern 1
    STOP (branch mismatch).
  - **C4** (defensive — DA-1-13): malformed `requires.land-pr.foo`
    missing `branch:` field → deny, Pattern 1 STOP (no branch-match
    found).
  - **C5**: `gh pr merge --auto`, no markers → deny.
  - **C6**: `gh pr merge --auto --squash`, no markers → deny.
  - **C7**: `gh pr merge --squash --auto`, no markers → deny
    (flag-order-agnostic).
  - **C8**: `gh pr merge --merge --auto`, no markers → deny.
  - **C9**: `gh pr merge` (no `--auto`), no markers → ALLOW (D4 / AC1.8).
  - **C10**: `gh issue create -t foo`, no markers → ALLOW (non-pr verb).
  - **C11**: `gh pr view 123`, no markers → ALLOW.
  - **C12**: `gh pr checks --watch`, no markers → ALLOW.
  - **C13**: `gh pr --help`, no markers → ALLOW.
  - **C14**: `gh --help`, no markers → ALLOW.
  - **C15**: `bash $CLAUDE_PROJECT_DIR/.claude/skills/land-pr/scripts/pr-push-and-create.sh ...`
    (the wrapper-script invocation that /land-pr itself uses), no
    markers → ALLOW (the inner `gh pr create` is NOT visible to the
    hook; the wrapper is what's being invoked).
  - **C16**: chained `cd /tmp/wt && gh pr create -B main`, no markers
    → deny (segment-walk).
  - **C17** (documented hole — DA-1-5): `bash -c 'gh pr create -B
    main'` → ALLOW (bash -c carve-out inherited from
    is_git_subcommand pattern; the Phase 4 negative-conformance assert
    is the source-side backstop).
  - **C18** (fail-open scope): `gh pr create` with
    `scripts/land-pr-bypass-message.sh` removed (chmod 0 or rm) →
    STILL DENY (hook gating is unconditional; only message-enrichment
    fails-open to the static fallback). Verify the static fallback
    STOP message is present in the deny envelope.
  - **C19**: `gh --repo foo/bar pr create` (2-token form), no markers →
    deny.
  - **C20**: `gh --repo=foo/bar pr create` (`=`-form), no markers → deny.
- [ ] **`docs/plans/CANARY_BYPASS_DETECT.md`** — a `/run-plan`-executable
  canary in two phases:
  - **Canary Phase 1**: sandbox-stub the hook's stdin via `bash
    .claude/hooks/block-bypassed-land-pr.sh < /tmp/stdin-fixture.json`
    and assert deny envelope is emitted for both Pattern 1 and Pattern
    2 inputs.
  - **Canary Phase 2**: synthesize a `/commit pr` end-to-end run that
    writes `requires.land-pr.$BRANCH_SLUG` + `fulfilled.commit.$BRANCH_SLUG`,
    then simulate a `bash $script` invocation of `/land-pr`'s
    wrapper-script (which the hook should NOT deny), and assert the
    wrapper-script invocation passes. Validates the carve-out
    architecture end-to-end.
- [ ] **Add canary to `docs/plans/RUN_ORDER_GUIDE.md`** (memory:
  feedback_rog_workflow) under the structural-defense canaries section.

### Design & Constraints

- **Sandbox-stub pattern**: `$CLAUDE_PROJECT_DIR=tmpdir`; do NOT touch
  live `.zskills/tracking/`. Cleanup via `trap "rm -rf $TMPDIR" EXIT`.
- **No `kill` / `pkill` / `fuser -k`** in tests (CLAUDE.md hard rule).
- **No mocked /land-pr execution** in the canary — only synthesis of
  marker fixtures + hook stdin envelopes. The canary doesn't actually
  push or create a PR.

### Acceptance Criteria

- [ ] AC5.1: `bash tests/test-block-bypassed-land-pr.sh` passes all 20
  test cases.
- [ ] AC5.2: `docs/plans/CANARY_BYPASS_DETECT.md` parses cleanly with
  `/run-plan` (manual smoke).
- [ ] AC5.3: The umbrella test runner includes the new test and passes
  green.
- [ ] AC5.4 (R-2-8): a dedicated test case verifies AC1.10's early-exit
  short-circuit. Stage an instrumented stub `scripts/land-pr-bypass-message.sh`
  that writes a marker to a tmp file on every invocation; run the hook
  on stdin commands NOT containing `"gh pr "` (e.g., `ls`, `cat /tmp/x`,
  `git commit -m foo`); assert the stub was NEVER invoked.
- [ ] AC5.5 (R-2-8): a dedicated test case verifies AC1.1's library
  sourcing — source `hooks/_lib/git-tokenwalk.sh` and call
  `is_gh_pr_subcommand "gh pr create -B main" create` directly; assert
  rc=0 + `GH_PR_SUB_INDEX` set.

### Dependencies

Phase 1 (hook), Phase 2 (caller markers for Canary Phase 2 synthesis),
Phase 3 (registration so the hook is in the active settings.json), Phase
4 (conformance anchor stability for STOP wording).

### Commit boundary

One commit: `test(hook): bypass-detect canary plan + 20-case integration test`.

## Phase 6 — metadata.version bumps + final mirror

### Goal

Per CLAUDE.md skill-versioning rule (C7), bump `metadata.version` on every
touched skill and mirror to `.claude/skills/`.

### Work Items

- [ ] **Skill version bumps** (compute hash via `scripts/skill-content-hash.sh
  <skill-dir>`; date in `America/New_York`):
  - `skills/commit/SKILL.md` — `modes/pr.md` edited in Phase 2 triggers
    parent bump.
  - `skills/do/SKILL.md` — same.
  - `skills/quickfix/SKILL.md` — direct edit in Phase 2.
  - `skills/fix-issues/SKILL.md` — `modes/pr.md` edited in Phase 2
    triggers parent bump.
  - `skills/land-pr/SKILL.md` — Phase 1 modifies the `fulfilled.land-pr.<id>`
    printf at line 533 to add the `branch:` field.
  - `skills/run-plan/SKILL.md` — Phase 2 adds `branch:` field to
    `requires.land-pr.<id>` write at line 851-855 (DA-2-2 fix).
  - `skills/update-zskills/SKILL.md` — install-triples table edited
    in Phase 3.
- [ ] **Final mirror to `.claude/skills/`** via batch `cp -a` (memory:
  feedback_claude_skills_permissions — edit source skills only, then
  batch-cp).
- [ ] **Final mirror to `.claude/hooks/`** for any concurrent edits since
  Phase 3 (`block-bypassed-land-pr.sh`, `_lib/git-tokenwalk.sh` if
  consumers mirror the lib).
- [ ] **Run full conformance** before committing:
  - `bash tests/test-skill-conformance.sh`
  - `bash tests/test-hook-helper-drift.sh`
  - `bash tests/test-block-bypassed-land-pr.sh`
  - Umbrella test runner if present (`tests/run-all.sh`).

### Design & Constraints

- **Date in `America/New_York`** for the version field per
  `scripts/skill-content-hash.sh` discipline.
- **No `--no-verify`** on the version-bump commit.
- **Skill versioning enforced at 4 points** (CLAUDE.md): warn-config-drift,
  /commit Phase 5 step 2.5, test-skill-conformance, PreToolUse backstop.
  The commit MUST pass all four.

### Acceptance Criteria

- [ ] AC6.1: `grep -E "metadata.version" skills/{commit,do,quickfix,fix-issues,land-pr,run-plan,update-zskills}/SKILL.md`
  shows today's date stamp on all 7.
- [ ] AC6.2: `bash scripts/skill-version-stage-check.sh` after staging
  the version-bumped SKILL.md files returns 0.
- [ ] AC6.3: `diff -r skills/ .claude/skills/` for the 6 touched skills
  shows no divergence (mirror is in sync).
- [ ] AC6.4: All tests pass (conformance, drift, hook integration,
  umbrella).

### Dependencies

Phase 2 (skill content edits), Phase 3 (hook + clear-tracking + manifest
edits), Phase 4 (conformance), Phase 5 (integration test).

### Commit boundary

One commit: `chore(skills): metadata.version bumps + final mirror for bypass-hardening`.

## Residual Risks (acknowledged + accepted)

The hook is best-effort runtime gating. These bypass surfaces are known
and either accepted, mitigated by source-conformance, or out of scope:

1. **`bash -c '<gh pr create ...>'` / `sh -c '...'` / `eval '...'`** —
   the tokenize-walker matches the outer command (`bash`, `sh`, `eval`),
   not the inner string. An agent that has learned this idiom can
   bypass. Mitigations:
   - Phase 4 source-conformance grep (AC4.5) catches the idiom in skill
     SOURCES.
   - Plan A precedent (`block-stale-skill-version.sh` test C10e) accepts
     the same hole for `git commit` enforcement. No runtime fix here
     either.
   - **NOT mitigated for runtime agent improvisation** outside skill
     source. The CLAUDE.md prose rule (line 140) and `feedback_hook_bypass`
     memory anchor are the soft-defenses.
2. **`! gh pr create` from REPL** — runs through Bash tool, fires the
   hook. Acknowledged cost (issue #224). Users who need true manual
   one-off operations open a separate terminal outside the Claude Code
   session.
3. **Mid-recovery partial-state cases** — if `/land-pr`'s wrapper script
   crashed between push and `gh pr create`, the agent cannot complete
   the PR creation by direct call. Recovery is: re-dispatch `/land-pr`
   (which is idempotent per `skills/land-pr/SKILL.md:592-606`). This
   constrains the agent to skill-mediated recovery only.
4. **Stale `requires.land-pr.<id>` across sessions** — the explicit-
   finalize at end of each caller's bash flow removes the marker, but
   if the caller's last bash fence didn't run (Claude session crashed
   mid-flow), the marker persists. Next session's hook would emit
   Pattern 2 wording (mid-flight) incorrectly. User can run
   `bash skills/update-zskills/scripts/clear-tracking.sh` to clear all `requires.*` markers
   (NOT preserved per D9 — they're transient by design).
5. **Pre-existing `fulfilled.land-pr.*` markers without `branch:` field**
   (legacy from before this plan) — STOP-message script treats as
   Pattern 2 fallback (DA-2-2 mitigation). Forward-compat preserved.
6. **Documentation false-positives on `bash -c '...gh pr...'` in plan
   files** — `docs/plans/*.md` is NOT scanned by the AC4.5 grep
   (`skills/` only). If plan files contain `bash -c 'gh pr create'`
   examples for documentation, they're exempt. Verify before adding
   the assert.
7. **Wave 1 cross-cutting dependency** — if Wave 1 (`skills/update-zskills/scripts/clear-tracking.sh`
   broad widening for `fulfilled.*.*`) lands AFTER this plan, this plan's
   narrow D9 patch is a strict subset and continues to work. If Wave 1
   lands BEFORE this plan, the narrow D9 patch is redundant — the
   regex-extension in this plan's Phase 3 work item must be re-checked
   against the Wave 1 final shape; expected outcome is "the new arm is
   already there, no-op."

## Drift Log

(Updated post-implementation by /run-plan / /refine-plan.)

| Date | Change | Reason |
|------|--------|--------|
|      |        |        |

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review
(orchestrator-judged max-rounds-reached)
**Convergence:** Max rounds reached — substantive Round 3 findings
addressed via final refinement pass without an additional review round.
Plan is shippable; remaining concerns enumerated in Residual Risks
section.
**Remaining concerns:** /quickfix's pre-existing trap-on-EXIT bug
(DA-3-3) is documented but NOT fixed in this plan — file as separate
Wave 1 follow-up. Wave 1's clear-tracking widening is a parallel
dependency (Residual Risks #7). All other findings dispositioned.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 (R-1-1..12)    | 13 (DA-1-1..13)           | 25/25 (5 no-action; rest fixed; DA-1-7 / DA-1-10 justified-not-fixed) |
| 2     | 13 (R-2-1..13)    | 10 (DA-2-1..10)           | 23/23 (Round 2 refinement complete) |
| 3     | 8 (R-3-1..8)      | 7 (DA-3-1..7, DA-3-8)     | 14/15 (DA-3-3 documented as pre-existing /quickfix bug — defer-fix scope decision) |

### Plan Review

#### Round 1 — disposition table

| Finding | Verification | Disposition |
|---------|--------------|-------------|
| R-1-1 (caller line numbers) | Verified by reviewer agent against worktree | No action needed |
| R-1-2 (tokenwalk `--repo` edge cases, `gh pr --help`) | Empirical from reading `is_git_subcommand` (`hooks/_lib/git-tokenwalk.sh:64-70`) | **Fixed** — Phase 1 D&C explicit on 1-token vs 2-token; AC1.9 added |
| R-1-3 (lock just-before-dispatch via conformance) | Judgment — convention | **Fixed** — Phase 4 textual-precedence assert added |
| R-1-4 (D6 fallback too permissive) | Judgment + Plan Phase 1 line 213-219 | **Fixed** — superseded by D1 unconditional-deny; markers no longer gate; mtime fallback dropped |
| R-1-5 (DAG) | Verified | No action |
| R-1-6 (STOP message recovery wording) | Judgment | **Fixed** — D8 branched STOP messages with explicit Skill-tool dispatch syntax |
| R-1-7 (settings.json ordering rationale wrong) | Verified — Claude Code PreToolUse hooks compose additively | **Fixed** — D1 + Phase 3 reworded to "order is cosmetic" |
| R-1-8 (/run-plan exclusion correctly verified) | Verified at `/run-plan/modes/pr.md:342` | No action |
| R-1-9 (AC for cross-skill exclusion) | Judgment | **Fixed** — AC2.8 regression assert |
| R-1-10 (plan format) | Verified | No action |
| R-1-11 (AC2.8 quickfix unchanged regression) | Judgment | **Fixed** — AC2.8 added |
| R-1-12 (commit-boundary discipline) | Verified per Plans A/B/C precedent | No action |
| DA-1-1 (sprint-shared PIPELINE_ID unlocks bypasses) | Verified at `skills/fix-issues/SKILL.md:459-463` + `modes/pr.md:52,88` | **Fixed** — D1 unconditional deny dissolves this entirely (markers don't gate; sprint-shared fulfilled markers don't unlock anything) |
| DA-1-2 (unified STOP misleads Pattern 2) | Verified via PR #221 evidence | **Fixed** — D8 branched STOP with Pattern 1 vs Pattern 2 wording |
| DA-1-3 (orphan requires markers) | Verified at `quickfix/SKILL.md:677` | **Fixed** — Phase 2 trap-on-EXIT cleanup added |
| DA-1-4 (clear-tracking wipes fulfilled.land-pr) | Verified at `skills/update-zskills/scripts/clear-tracking.sh:48-52` | **Fixed** — D9 narrow scope-fence + Phase 3 patch (subset of Wave 1) |
| DA-1-5 (bash -c hole + missing source-conformance) | Verified — Phase 4 had only positive asserts | **Fixed** — Phase 4 negative grep asserts added (AC4.5, AC4.6) |
| DA-1-6 (D3 source-vs-runtime framing) | Judgment | **Fixed** — D3 reworded with explicit source-vs-runtime clarification |
| DA-1-7 (BOTH-probe namespace collision) | Speculative | **Justified-not-fixed** — PIPELINE_IDs are skill-prefixed (`commit.X` vs `quickfix.X` vs `do.X` vs `fix-issues.X` vs `run-plan.X`) so collision requires explicit construction; documented in D6 |
| DA-1-8 (D7 misreads #228 Part B per-skill markers) | Verified at issue #228 body | **Fixed** — D7 revised to write per-skill `fulfilled.<skill>.<id>` for `/commit`, `/do`, `/fix-issues`; Phase 2 work items added |
| DA-1-9 (perf — early-exit before script spawn) | Judgment | **Fixed** — Phase 1 bash-only early-exit short-circuit added; AC1.10 |
| DA-1-10 (settings.json consumer customization) | Speculative | **Justified-not-fixed** — Phase 3 work item adds a documentation note; full merge-installer design is out of scope |
| DA-1-11 (Unicode bullets + backtick anchor) | Verified | **Fixed** — STOP message ASCII-only; conformance anchor without backtick |
| DA-1-12 (rationale wording at line 385-394) | Judgment | **Fixed** — Phase 2 D&C reworded |
| DA-1-13 (C4 inconsistency) | Verified at /land-pr SKILL.md:510-538 | **Fixed** — C4 renamed "defensive" and clarified |

#### Round 2 — disposition table

| Finding | Verification | Disposition |
|---------|--------------|-------------|
| R-2-1 (D9 clear-tracking spec against wrong file shape) | Verified by reading `skills/update-zskills/scripts/clear-tracking.sh:46-58, 150-157` — separate per-class arms; residual assertion doesn't list new families | **Fixed** — D9 reworded; preserve-arm extension specified correctly; residual assertion explicitly NOT touched |
| R-2-2 ("1-line edit" misframed) | Verified at `/land-pr SKILL.md:533` — printf has format string + arg line | **Fixed** — Phase 1 D&C reworded "modifies two physical lines but one logical change"; backward-compat for legacy markers documented |
| R-2-3 (`-R\|--repo` cases explicit in is_gh_pr_subcommand) | Judgment — comparing to is_git_subcommand:64-70 | **Fixed** — Phase 1 Work Items make the `-R\|--repo` walking explicit |
| R-2-4 (orphan `requires.land-pr.*` on caller rc=0 with pr-ready settle) | Judgment | **Fixed** — explicit-finalize block always removes requires (not gated on rc); transient-diagnostic semantics |
| R-2-5 (test source not covered by negative grep) | Verified | **Fixed** — AC4.5 grep spec restricted to `skills/` only; documentation false-positives noted in Residual Risks |
| R-2-6 (test-fixture impact verified clean) | Verified | No action |
| R-2-7 (detached-HEAD path correct but unasserted) | Verified | **Fixed** — explicit detached-HEAD handling in `land-pr-bypass-message.sh` work item |
| R-2-8 (AC1.10 coverage gap in Phase 5) | Verified | **Fixed** — AC5.4 added |
| R-2-9..13 (lower-severity) | Mostly judgment | Various — covered or dismissed per disposition |
| R-2-12 BLOCKING (trap-on-EXIT lifecycle mismatch across bash fences) | Verified by reading SKILL.md structures + checking trap semantics across separate Bash tool invocations | **Fixed** — Phase 2 replaces trap-on-EXIT with explicit-finalize at end of last bash fence; uses explicit `$LAND_OUTCOME` variable not `$?` |
| DA-2-1 BLOCKING (every `break` returns rc=0; trap stamps `complete` on failed lands) | Verified at `skills/commit/modes/pr.md:68-215` — every break is rc=0 | **Fixed** — explicit `$LAND_OUTCOME` tracking in case arms; AC2.10 negative-test |
| DA-2-2 BLOCKING (/run-plan requires.land-pr.<id> lacks `branch:` field) | Verified at `skills/run-plan/SKILL.md:851-855` — no branch field | **Fixed** — Phase 2 work item adds branch field to /run-plan; AC2.9; /run-plan added to Phase 6 version bumps |
| DA-2-3 (Phase 3 preserves bogus markers from DA-2-1) | Verified | **Fixed-by-dependency** — DA-2-1 fix removes the bogus-marker source |
| DA-2-4 (orphan-requires Pattern 2 false-positive — duplicate of R-2-4) | Verified | **Fixed** — same fix as R-2-4 (explicit-finalize always cleans up requires) |
| DA-2-5 (no Residual Risks section) | Judgment | **Fixed** — Residual Risks section added with 7 enumerated items |
| DA-2-6 (Phase 4 AC4.5 grep edge cases — `bash -c` no-space, `sh -c`, `eval`) | Verified by tracing the regex | **Fixed** — Phase 4 grep spec expanded: `(bash\|sh)[[:space:]]+-c` + separate `eval` regex |
| DA-2-7 (AC4.6 may pre-fail on current /land-pr SKILL.md) | Judgment | **Fixed** — Phase 4 spec adds "pre-verify before adding assert" guidance |
| DA-2-8 (wrapper-script carve-out not empirically tested) | Verified | **Fixed** — Phase 5 C15 specifically tests the wrapper-script case |
| DA-2-9 (perf chained-command tokenize-walk) | Speculative | **Justified-not-fixed** — segment-walk is bounded by command length; the early-exit short-circuit at hook entry skips non-`gh pr` commands |
| DA-2-10 (STOP message tells agent to check `--result-file` it may not have) | Judgment | **Fixed** — STOP message Pattern 2 refers to "the caller-loop pattern at `skills/land-pr/references/caller-loop-pattern.md`" rather than a specific result-file path |

#### Round 3 — disposition table

| Finding | Verification | Disposition |
|---------|--------------|-------------|
| R-3-1 BLOCKING (`$BRANCH_NAME` out of scope at line 851) | Verified at `skills/run-plan/SKILL.md:1212` — variable defined ~360 lines later | **Fixed** — Phase 2 spec changed to inline `git symbolic-ref --short HEAD` |
| R-3-2 BLOCKING (`pr-ready` not a STATUS value; LAND_OUTCOME tracking incomplete) | Verified at `skills/commit/modes/pr.md:124-145` — STATUS arms are {rebase-conflict, push-failed, ..., created, monitored, merged} only | **Fixed** — Phase 2 marker-lifecycle pattern now specifies LAND_OUTCOME tracked in BOTH STATUS arms AND inner CI_STATUS settle arms; default `unknown` initialization; comprehensive mapping to FINAL |
| R-3-3 BLOCKING (Phase 4 asserts still say "trap" — stale from Round 2) | Verified at original Phase 4 D&C | **Fixed** — Phase 4 positive asserts revised to check for `explicit-finalize` block (sed-rewrite + rm-requires line), not trap |
| R-3-4 BLOCKING (AC4.5 grep #1 false-positives on `/land-pr SKILL.md:601` prose mention) | Verified empirically: line 601 ` `gh pr create` again. The script does NOT call \`gh pr edit\`` | **Fixed** — regex updated with backtick-exclusion anchors |
| R-3-5 NEW GAP (path is `skills/update-zskills/scripts/clear-tracking.sh`, not `scripts/clear-tracking.sh`) | Verified via `find` | **Fixed** — all references updated |
| R-3-6 NEW GAP (no behavioral AC for /run-plan branch field) | Judgment | **Fixed** — AC2.9 already covers static-read assert; AC4 conformance includes /run-plan SKILL.md branch field check |
| R-3-7 / R-3-8 (Overview wording / Residual Risk path) | Judgment | **Fixed** — Overview revised to acknowledge /run-plan's branch-field + finalize additions |
| DA-3-1 BLOCKING (`exit 1` paths bypass explicit-finalize) | Verified at `skills/commit/modes/pr.md:96` | **Fixed** — Phase 2 work items add inline cleanup before each defensive `exit 1` |
| DA-3-2 BLOCKING (LAND_OUTCOME unset for CI_STATUS settle paths) | Verified — duplicate of R-3-2 | **Fixed** — same fix as R-3-2 |
| DA-3-3 (`/quickfix` trap-on-EXIT fires immediately at end of setting fence — pre-existing bug) | Verified by inspection (21+ bash fences in /quickfix; trap doesn't cross fences) | **Documented, deferred** — D7 acknowledges as pre-existing bug; this plan does NOT fix it (scope creep); file as Wave 1 follow-up. #228 Part B AC marked as partial-met for /quickfix |
| DA-3-4 BLOCKING (/run-plan caller-loop missing explicit-finalize cleanup) | Verified at `skills/run-plan/modes/pr.md:536` — no rm-requires after caller-loop | **Fixed** — Phase 2 work item explicitly adds the cleanup at line 537+ |
| DA-3-5 (= R-3-1 dup) | | **Fixed** (same as R-3-1) |
| DA-3-6 (empty-stderr defensive gap) | Judgment | **Fixed** — Phase 1 hook spec adds "empty or short stderr → static fallback" defensive condition |
| DA-3-7 (= portion of DA-3-3) | | **Documented** (same as DA-3-3) |
| DA-3-8 (no Wave-1-already-landed pre-flight) | Speculative | **Justified-not-fixed** — Phase 6 runs full conformance before commit; if Wave 1 has already landed and broadened the case statement, this plan's narrow patch becomes a no-op (the new arm is already a subset); no special detection needed |
