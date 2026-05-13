---
title: Close /land-pr Bypass Hole — Caller Tracker Parity + PreToolUse Hook
created: 2026-05-12
status: complete
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
   wires (commit `2bdbeda`, PR #219; see the `requires.land-pr.<id>`
   write block in Phase 1 Step 8's tracking fence at
   `skills/run-plan/SKILL.md` — currently lines 870-874, anchor: the
   `printf 'skill: land-pr\nparent: run-plan\nid: %s\ndate: %s\n'`
   block) across the other four callers.
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
the `/run-plan` SKILL.md tracking-marker convention in Phase 1 Step 8
— currently around line 844 where `PIPELINE_ID` is constructed via
`"${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"`).

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
`/run-plan` already writes `fulfilled.run-plan.<id>` (anchor: the
`printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: started\ndate: %s\n'`
block in Phase 1 Step 8, currently `skills/run-plan/SKILL.md:846-848`);
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

This plan satisfies #228 Part B's literal AC for `/commit`, `/do`,
`/fix-issues`, `/run-plan`, `/land-pr` only.

**`/quickfix`'s AC is structurally unmet (R-4-18 / DA-4-9 hedge
strengthening).** The `fulfilled.quickfix.<slug>` marker exists, but
its `status` field cannot be trusted until issue #241's trap bug is
fixed: `trap 'finalize_marker $?' EXIT` (SKILL.md:677) fires when the
*setting* fence exits — which is `rc=0` immediately, stamping
`status: complete` on entry rather than on actual /quickfix completion.
Aborted /quickfix runs (any `exit 1/2/5/6` path between fence 631-678
entry and the actual caller-loop completion at line 1244) ALSO report
`status: complete`. /quickfix is therefore documented-deferred from
#228 Part B until #241 lands. **Dashboard consumers should treat
`fulfilled.quickfix.<slug>` entries as 'attempted, not necessarily
completed' until #241 lands** — explicitly document this consumer-side
caveat so downstream code does not trust the status field for
/quickfix.

The markers are **independent of and parallel to** `fulfilled.land-pr.<id>`
(which signals merge, not skill-completion).

**D8. STOP-message wording branches on tracking state.** When the hook
denies, it inspects `.zskills/tracking/*/requires.land-pr.*` (in BOTH
MAIN_ROOT and WORKTREE_ROOT) and reads the body's `branch:` field:
- **Pattern 2** (requires.land-pr.* with `branch: <current HEAD>` exists)
  → "Your `/land-pr` invocation appears to have errored mid-flight. The
  recovery is to fix the `/land-pr` args (check the `--result-file` for
  the failure reason and the caller-loop pattern at
  `skills/land-pr/references/caller-loop-pattern.md`), NOT to fall back
  to direct `gh pr create` / `gh pr merge --auto`. If you believe this
  is a stale marker from a prior crashed session, run
  `bash skills/update-zskills/scripts/clear-tracking.sh` to clear and
  retry." (DA-4-11)
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
modification** — verified empirically against the source (DA-4-10:
quoted in plan for self-contained verifiability):
```bash
residual=$(find "$TRACKING_DIR" -type f \
  \( -name 'requires.*' \
     -o -name 'step.*' -o -name 'phasestep.*' \
     -o -name 'fulfilled.verify-changes.*' \
     -o -name 'fulfilled.draft-plan.*' \
     -o -name 'fulfilled.refine-plan.*' \
     -o -name 'verify-pending-attempts.*' \) \
  | wc -l | tr -d ' ')
```
It lists *classes that SHOULD have been cleared* (`requires.*`,
`step.*`/`phasestep.*`, `fulfilled.verify-changes.*`,
`fulfilled.draft-plan.*`, `fulfilled.refine-plan.*`,
`verify-pending-attempts.*`), and the new preserved markers
(`fulfilled.land-pr.*`, `fulfilled.commit.*`, `fulfilled.do.*`,
`fulfilled.fix-issues.*`, `fulfilled.quickfix.*`) are not among them.
The "lockstep" concern from `97c7d19`'s commit message applies when
we change which markers are *cleared*, which this plan doesn't.
(R-2-1 verification correction; R-4-11 contradiction resolution;
DA-4-10 in-plan verifiability.)

Wave 1 will subsume this with a broader `fulfilled.*.*` rule; this
narrow patch is strictly a subset and lands here to avoid hard cross-
plan ordering coupling. (DA-1-4 resolution.)

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — tokenize-walk helper + hook | ✅ Done | `eaccbf4` | new `is_gh_pr_subcommand` + `block-bypassed-land-pr.sh`; land-pr version bumped inline (plan-drift, see report) |
| 2 — Caller edits (4 skills) | ✅ Done | `71f8770` | `requires.land-pr.<id>` + `--tracking-id` + new `fulfilled.<skill>.<id>`; 5 skill versions bumped inline (plan-drift, see report) |
| 3 — Hook registration + clear-tracking narrow widening | ✅ Done | `994321f` | `.claude/settings.json` + mirror + clear-tracking patch (TWO arms — spec only had one; surfaced + fixed); update-zskills version bumped inline |
| 4 — Conformance tripwires | ✅ Done | `013071d` | +35 conformance asserts +2 drift-gate asserts; tier-1 hash for clear-tracking added inline (Phase 3 regression fix); update-zskills re-bumped |
| 5 — Hook integration test + canary | ✅ Done | `2568831` | `tests/test-block-bypassed-land-pr.sh` (26 cases) + `docs/plans/CANARY_BYPASS_DETECT.md`; ROG row deferred per ROG workflow |
| 6 — metadata.version bumps + final mirror | ✅ Done | (verify-only) | all 7 skill bumps + mirrors completed inline in Phases 1-4 (plan-drift); 2933/2933 final conformance gate |

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
  - **Defensive: sentinel-anchored static fallback** (DA-3-6 fix +
    R-4-4 refinement + DA-5-5 sentinel-strengthening). If the
    message-script exited but `$STDERR` does NOT contain the canonical
    anchor `STOP: direct gh pr`, use the static fallback STOP message
    text below instead of the captured stderr. Concretely:
    ```bash
    if ! printf '%s' "$STDERR" | grep -qF 'STOP: direct gh pr'; then
      USE_STATIC_FALLBACK=1
    fi
    ```
    Rationale (DA-5-5 escalation): the prior "empty after whitespace
    strip" check handled the "script bug → rc=1 with no body" case but
    did NOT handle the "script bug → bash error trace as stderr" case
    (e.g., `bash: scripts/land-pr-bypass-message.sh: line 47: foo:
    command not found`). Without the sentinel check, that error trace
    would be served verbatim as `permissionDecisionReason`, exposing
    internal stack-traces to the agent and confusing the
    Pattern 1 / Pattern 2 distinction — risking the agent
    misinterpreting "the hook itself is broken — try `bash -c` bypass."
    Anchoring on the canonical `STOP: direct gh pr` sentinel proves
    the script ran to completion correctly. This subsumes the previous
    "empty after whitespace-strip" check (empty stderr also lacks the
    anchor → falls back). The "shorter than 50 chars" threshold from
    the pre-Round-1 plan was arbitrary; sentinel-based is principled.

    **AC1.6b (new) — sentinel-anchored fallback:** synthesize a
    bypass-trigger PreToolUse stdin envelope, then run the hook with
    `scripts/land-pr-bypass-message.sh` replaced by a stub that emits
    `bash: scripts/land-pr-bypass-message.sh: line 47: foo: command not found`
    to stderr (a synthetic bash error trace, NO `STOP: direct gh pr`
    anchor). Assert the deny envelope's `permissionDecisionReason`
    equals the STATIC fallback text (NOT the bash error trace).
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
  - Pattern 2 also contains (DA-4-11 stale-marker recovery hint):
    `clear-tracking.sh` (anchor substring; full sentence per D8).
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
- [ ] AC1.7: Hook matches arbitrary flag-order permutations of
  merge+auto (the helper is documented flag-order-agnostic). DA-5-6
  generalized to programmatic enumeration: for every combination of
  `--auto` (required) × subset of `{--squash, --merge, --rebase}`
  (at most one merge-strategy flag) × `{--delete-branch, absent}`,
  test every permutation of the chosen flags. The combinatorial set is
  ~24 commands. All MUST deny. Representative subset (all must pass):
  - `gh pr merge --auto`
  - `gh pr merge --auto --squash`
  - `gh pr merge --squash --auto`
  - `gh pr merge --merge --auto`
  - `gh pr merge --auto --squash --delete-branch` (3-flag, --auto first)
  - `gh pr merge --squash --auto --delete-branch` (3-flag, --auto middle)
  - `gh pr merge --delete-branch --squash --auto` (3-flag, --auto last
    — the common /land-pr `pr-merge.sh` shape)
  - `gh pr merge --rebase --auto`
  - `gh pr merge --auto --rebase --delete-branch`
  - `gh pr merge --delete-branch --rebase --auto` (DA-5-6 fix —
    `--auto` last with `--rebase` middle)
  - `gh pr merge --delete-branch --merge --auto`
  - `gh pr merge --auto --merge --delete-branch`
  AC fails if any permutation allows. Implementer-agent SHOULD generate
  the full ~24-perm set programmatically (e.g., python `itertools.permutations`)
  rather than hand-enumerating; the list above is the
  ground-truth subset that MUST pass.
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
    on the settle (mapping covers ALL arms present in source —
    R-4-6 / DA-4-2 blocking fix — including the `unknown` and `*`
    catch-all arms whose source comments say "settle at pr-ready"):
    - `pass|none|skipped` and PR_STATE=MERGED → `LAND_OUTCOME=merged`
    - `pass|none|skipped` and PR_STATE=OPEN → `LAND_OUTCOME=pr-ready`
    - `pending` → `LAND_OUTCOME=pr-ready`
    - `not-monitored` → `LAND_OUTCOME=created`
    - `fail` after fix-cycle exhaustion → `LAND_OUTCOME=pr-ci-failing`
      (R-5-4 exact insertion point: in the `fail)` case arm, INSIDE the
      `if [ "$ATTEMPT" -ge "$MAX" ]; then` block, IMMEDIATELY BEFORE
      the existing `break` statement. Verified shape from
      `skills/commit/modes/pr.md:145-148`:
      ```bash
      fail)
        if [ "$ATTEMPT" -ge "$MAX" ]; then
          echo "INFO: CI fix-cycle exhausted ..." >&2
          LAND_OUTCOME=pr-ci-failing   # ← INSERT HERE
          break
        fi
        # ... fix-cycle dispatch ...
        ATTEMPT=$((ATTEMPT + 1))
        continue ;;
      ```
      DO NOT set `LAND_OUTCOME` outside the `if` (would fire on every
      pre-exhaustion iteration). DO NOT set after `break` (unreachable).
      Same shape applies symmetrically to all 5 callers — verified by
      grep: `commit/modes/pr.md:145`, `do/modes/pr.md`,
      `run-plan/modes/pr.md`, `fix-issues/modes/pr.md`,
      `quickfix/SKILL.md` all have the identical `fail)` /
      `if ATTEMPT >= MAX` / `break` structure per the canonical
      caller-loop pattern.)
    - `unknown` → `LAND_OUTCOME=pr-ready` (matches source comment at
      `skills/commit/modes/pr.md:196` "settle at pr-ready" — and the
      mirrored arms in `/do/modes/pr.md`, `/run-plan/modes/pr.md`)
    - `*` (catch-all) → `LAND_OUTCOME=pr-ready` (matches source
      comment at `skills/commit/modes/pr.md:199` "settle at pr-ready")
  - **Default initialization** at top of caller-loop:
    `LAND_OUTCOME=__init__` (R-5-8 — renamed from `unknown` to avoid
    token-overload with the CI_STATUS=`unknown` arm which maps to
    `pr-ready`; same identifier with opposite semantics was a
    cognitive trap for verifiers reading the case statement). If the
    loop exits with LAND_OUTCOME still `__init__` (i.e., the loop
    broke before any case arm set it, which should not happen given
    the comprehensive case coverage above), the explicit-finalize's
    `*) FINAL=failed` default catches it. With the case-arm
    CI_STATUS=`unknown` and `*) ` mapped to `pr-ready`, this
    default-tail fires ONLY on truly unreachable paths (e.g., the
    loop exits via an unstructured `break` we haven't enumerated).
  - **`continue` semantics (DA-4-6).** The inner `case "$CI_STATUS"`'s
    `fail`-before-exhaustion arm `continue`s back to the loop top
    WITHOUT touching LAND_OUTCOME — this is deliberate; the next loop
    iteration's `break` (whatever arm it lands in) will set LAND_OUTCOME
    correctly. Only `fail`-AFTER-exhaustion (`ATTEMPT >= MAX`, `break`
    path) sets `LAND_OUTCOME=pr-ci-failing`. Default-`unknown`
    initialization at the top of the loop AND the `unknown → pr-ready`
    + `*) → pr-ready` arms together ensure that any unreached-tail
    cases default to a success-equivalent FINAL rather than `failed`.
- After the caller-loop completes (`# === END CANONICAL /land-pr CALLER
  LOOP ===`), apply the explicit-finalize:
  - `FINAL=complete` if `$LAND_OUTCOME ∈ {merged, created, pr-ready}`
    (R-5-7: `monitored` removed — the inner CI_STATUS case never
    assigns `LAND_OUTCOME=monitored`; the outer `created|monitored|merged)`
    STATUS arm is a no-op fall-through to the inner CI_STATUS case,
    which then sets one of {merged, pr-ready, created, pr-ci-failing}.
    No source path produces `LAND_OUTCOME=monitored`.)
  - `FINAL=failed` if `$LAND_OUTCOME ∈ {rebase-conflict, push-failed,
    create-failed, merge-failed, monitor-failed, rebase-failed,
    pr-ci-failing, __init__}` (R-5-8: `__init__` replaces `unknown`
    as the unreachable-tail sentinel; the CI_STATUS=`unknown` arm
    maps to `LAND_OUTCOME=pr-ready` which is success-equivalent —
    different runtime value from the default-init sentinel)
  - `FINAL=cancelled` if `$CANCELLED -eq 1`
  - `sed -i "s/^status: started$/status: $FINAL/"` on the fulfilled
    marker.
- ALWAYS remove `requires.land-pr.<id>` at this final step (regardless
  of outcome — transient diagnostic).

**Same-fence requirement (R-4-7 / DA-4-4 BLOCKING fix).** The
explicit-finalize block MUST be inserted INSIDE the same `` ```bash
... ``` `` fence as the caller-loop (i.e., between the `# === END
CANONICAL /land-pr CALLER LOOP ===` marker line and the closing
triple-backtick of that fence), NOT in a new bash fence after the
closing triple-backtick. This is non-negotiable for correctness:

- All 5 callers have BEGIN/END CANONICAL inside ONE bash fence
  (verified by `grep -n '^\`\`\`' <file>`):
  - `/commit pr` — fence 68-215, END CANONICAL at 214
  - `/do pr` — fence 181-329, END CANONICAL at 328
  - `/quickfix` — fence 1071-1245, END CANONICAL at 1244
  - `/fix-issues pr` — caller-loop fence with END CANONICAL at 232
  - `/run-plan modes/pr.md` — fence 291-543, END CANONICAL at 542
- `$LAND_OUTCOME` is set by case arms INSIDE the caller-loop fence;
  variables do NOT survive across bash fences (separate Bash tool
  invocations, separate shell sessions — explicitly noted in
  `skills/run-plan/SKILL.md:1326-1328` "Resolve config-derived vars at
  fence-top — context compaction may have lost vars set in earlier
  fences").
- If the implementer adds the explicit-finalize as a NEW bash fence
  after the caller-loop fence, `$LAND_OUTCOME` is unset in the new
  fence → case statement falls to `*) FINAL=failed` → every
  successful run stamps `status: failed`. This silently breaks the
  dashboard's activity feed for ALL 5 callers.
- The per-caller Work Items below use language like "append a finalize
  block" — read this as "insert the finalize block immediately after
  the `# === END CANONICAL ... ===` line, BEFORE the closing
  ` ``` ` of the same fence." Do NOT start a new fence.

Phase 4 conformance grep-anchors on this property (see
"sed/rm-must-be-inside-fence" assert).

**Defensive `exit 1` paths (DA-3-1 + R-4-9 / DA-4-8).** Each caller
has defensive `exit 1` paths that bypass the explicit-finalize. The
plan's enforcement strategy varies by caller based on how many
`exit` paths exist and where they sit relative to the marker-setup
site:

**`/commit pr`, `/do pr`, `/fix-issues pr` — INLINE CLEANUP REQUIRED**
(small, enumerable exit count, all AFTER marker-setup):
- `/commit modes/pr.md:96` (inside caller-loop fence; RESULT_FILE
  missing). Prepend inline cleanup before this `exit 1`:
  ```bash
  rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
  sed -i "s/^status: started$/status: failed/" "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG"
  exit 1
  ```
  Variables are in scope at line 96 (same fence as the marker setup).
- `/do modes/pr.md:210` — same shape with `$TASK_SLUG`.
- `/fix-issues modes/pr.md` — verify exit-1 count via `grep -nE
  "^\s*exit [0-9]" skills/fix-issues/modes/pr.md`; per current source,
  zero such exits between per-issue marker-setup and per-issue
  explicit-finalize, so no inline cleanup needed (but verify before
  shipping; if any are added during the implementation pass, retrofit
  per the /commit pattern).
- `/run-plan modes/pr.md` — single `exit 1` at line ~360 (after the
  caller-loop, in PR-body sync); this is AFTER explicit-finalize so
  the requires.land-pr marker was already removed — no inline cleanup
  needed. Confirm via line numbers before shipping.

**`/quickfix` — ACCEPT THE RISK + DOCUMENT** (DA-4-8 BLOCKING fix /
R-4-9 enumeration):
- `grep -nE "^\s*exit [0-9]" skills/quickfix/SKILL.md` returns 11
  `exit 1` paths (lines 58, 157, 193, 209, 213, 235, 259, 267, 704
  + multiple `exit 2/5/6` paths). Many are PRE-marker-setup (the
  marker-setup is at fence 631-678; exits at lines 58-295 are before).
  Pre-marker-setup exits leave no marker to clean up — no action
  needed there.
- Post-marker-setup `/quickfix` exits (line 704 onward) leave
  `requires.land-pr.$SLUG` and `fulfilled.quickfix.$SLUG started`
  orphaned. Retrofitting all 11+ exits with `$TRACK_DIR`/`$SLUG`
  re-resolution (per DA-4-5 fix pattern) is mechanically possible
  but adds substantial surface area to this plan and risks
  introducing bugs in /quickfix's existing tested flow.
- **Decision: accept the orphan-marker risk for /quickfix mid-exit
  paths.** Document explicitly in Residual Risks (#8 — new entry):
  "/quickfix has 11+ `exit 1/2/5/6` paths between fence 631-678
  marker-setup and the line 1244 explicit-finalize. Any exit on
  these paths leaves `requires.land-pr.$SLUG` orphaned (recovered
  by `bash skills/update-zskills/scripts/clear-tracking.sh` or next
  session's marker overwrite) AND leaves
  `fulfilled.quickfix.$SLUG status: started` (pre-existing bug per
  D7 / #241 — orthogonal to this plan)." This is honest scoping,
  not a fix-all-or-fail blocker.

**Phase 4 conformance backstop.** Phase 4's positive-precedence
assert enforces that the marker-setup write block appears textually
BEFORE the `LAND_ARGS=` line; it does NOT enforce inline cleanup
before every `exit` path (that's effectively unenforceable without a
control-flow analyzer). The inline-cleanup requirement above is for
the specific named exits in /commit and /do only — both are listed
explicitly so future skill edits adding new exits will need the
plan reader to consciously decide whether to retrofit cleanup or
accept the risk per the /quickfix precedent.

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
    # R-5-6: `cancelled)` arm omitted — `CANCELLED` is /quickfix-only;
    # `LAND_OUTCOME=cancelled` is never assigned by /commit pr's
    # case-arm machinery. The `*) FINAL=failed` default-tail covers
    # any unexpected unreachable path.
    case "$LAND_OUTCOME" in
      merged|created|pr-ready) FINAL=complete ;;
      *) FINAL=failed ;;
    esac
    sed -i "s/^status: started$/status: $FINAL/" "$TRACK_DIR/fulfilled.commit.$BRANCH_SLUG"
    rm -f "$TRACK_DIR/requires.land-pr.$BRANCH_SLUG"
    ```
    Same case-statement shape (4 success-class arms, no `cancelled`
    arm, `*` default-failed) applies to `/do pr`, `/fix-issues pr`,
    `/run-plan modes/pr.md`. /quickfix retains its existing trap +
    `cancelled` semantics (out of scope per Decisions D7).
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
    fulfilled.quickfix write block (inside the fence 631-678, before
    the closing ` ``` ` at line 678), with `branch: $BRANCH` field.
    At this site `$TRACK_DIR`, `$SLUG`, `$BRANCH`, `$NOW_ISO` are all
    in scope (verified in fence A at lines 633-647).
  - **DA-4-5 BLOCKING fix — `$TRACK_DIR` and `$SLUG` are out of scope
    at the new cleanup site (line 1244).** The caller-loop fence
    1071-1245 is a SEPARATE bash invocation from fence A (631-678)
    where `$TRACK_DIR` and `$SLUG` were defined; variables do NOT
    survive across fences. Adding `rm -f "$TRACK_DIR/requires.land-pr.$SLUG"`
    naively at line 1244 expands to `rm -f "/requires.land-pr."`
    (with empty `$TRACK_DIR` → leading `/` ; empty `$SLUG` → no
    file-specific suffix) — silently fails to remove the marker.

    **Resolution: pattern-based cleanup using a glob over the pipeline
    subdir (R-5-5 fix — supersedes Round-1's circular
    `SLUG="${BRANCH#quickfix/}"` fallback).** Round 2 audit confirmed
    that `$SLUG` and `$BRANCH` are BOTH out of fence-scope at line
    1244 (the caller-loop fence 1071-1245 contains no runtime
    `SLUG=` or `BRANCH=` assignments — verified by
    `awk 'NR>=1071 && NR<=1245' skills/quickfix/SKILL.md |
    grep -nE '^[[:space:]]*(SLUG|BRANCH)='` → empty). /quickfix's
    convention is **model-substitution across fences**: Claude reads
    `$SLUG`/`$BRANCH` set in earlier prose and substitutes the literal
    value when emitting the next fence. This contract is implicit and
    fragile to rely on for runtime correctness in cleanup.

    Instead of re-deriving `$SLUG` (which has no in-scope source at
    the cleanup site), use a **best-effort glob cleanup** scoped to
    the active /quickfix pipeline. At the **end of the caller-loop**
    (after `# === END CANONICAL /land-pr CALLER LOOP ===` line 1244
    and BEFORE the closing ` ``` ` at line 1245 — same-fence
    requirement per R-4-7), insert:
    ```bash
    # Cleanup transient requires marker (R-5-5 / DA-4-5 — best-effort
    # since $SLUG is out-of-fence-scope and the only reliable
    # reconstruction path would require re-running /quickfix's
    # branch-derivation logic, which is fragile). Glob cleanup
    # targets ANY requires.land-pr.* in the active quickfix.* pipeline
    # subdir under MAIN_ROOT; the find-rm pattern is safe because
    # only the current invocation's requires.land-pr.<id> can exist
    # there at this point (pre-existing requires would have been
    # cleaned by prior invocations or by /update-zskills clear-tracking).
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
    # If ZSKILLS_PIPELINE_ID is set (passed via env from the orchestrator),
    # target its specific subdir; otherwise glob across quickfix.*.
    if [ -n "$ZSKILLS_PIPELINE_ID" ]; then
      rm -f "$MAIN_ROOT/.zskills/tracking/$ZSKILLS_PIPELINE_ID/requires.land-pr."*
    else
      # Fallback: glob ALL quickfix.* subdirs. Acceptable per Residual
      # Risk #8 (cleanup race); orphans recovered by clear-tracking.sh.
      find "$MAIN_ROOT/.zskills/tracking" \
        -maxdepth 2 -type d -name 'quickfix.*' \
        -exec sh -c 'rm -f "$1"/requires.land-pr.*' _ {} \;
    fi
    ```

    The `$MAIN_ROOT` IS in scope because the fence-top sources
    `zskills-resolve-config.sh` which sets it. The `$ZSKILLS_PIPELINE_ID`
    branch handles the typical case (env-propagated from the
    orchestrator); the glob fallback handles the case where /quickfix
    was invoked without that env. The fulfilled.quickfix finalize is
    already handled by /quickfix's existing trap; this block just
    cleans up the new requires marker so it doesn't orphan across
    sessions.

    **Why not re-derive `$SLUG`?** The only in-scope reconstruction
    paths are (a) `git symbolic-ref --short HEAD` (returns the
    quickfix-prefixed branch name, but stripping the prefix requires
    knowing the prefix, which is config-derived AND not necessarily
    in scope), and (b) re-running /quickfix's full branch-derivation
    machinery (substantial surface area inside a cleanup block). The
    glob approach is best-effort by design and aligns with /quickfix's
    documented Residual Risk #8 (cleanup race acceptable).
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

- [ ] **`/run-plan` SKILL.md — add `branch:` field to the
  `requires.land-pr.<id>` write block (DA-2-2 + R-3-1 + R-4-2 / DA-4-1
  fix).** Modify the existing `requires.land-pr.<id>` write inside the
  Phase 1 Step 8 tracking-marker fence (currently lines 870-874; anchor:
  the `printf 'skill: land-pr\nparent: run-plan\nid: %s\ndate: %s\n'`
  block guarded by `if [ "$LANDING_MODE" = "pr" ]; then`) to include
  the branch field. Current shape:
  `printf 'skill: land-pr\nparent: run-plan\nid: %s\ndate: %s\n'`;
  new shape:
  `printf 'skill: land-pr\nparent: run-plan\nid: %s\nbranch: %s\ndate: %s\n'`
  with the branch name as the new arg.

  **Branch-name resolution at the write site (R-4-2 / DA-4-1 blocking
  fix — supersedes R-3-1's `git symbolic-ref` proposal).** Phase 1
  Step 8 runs BEFORE Phase 2 creates the worktree and `cd`'s into it;
  therefore the bash fence runs in the orchestrator's CWD (typically
  `$CLAUDE_PROJECT_DIR` on `main`). Both R-3-1's proposed
  `git symbolic-ref --short HEAD` AND the previously-considered
  `$BRANCH_NAME` (defined at `skills/run-plan/SKILL.md:1263`, ~390
  lines after the write site) resolve to the WRONG branch:
  - `git symbolic-ref --short HEAD` returns `main` (the orchestrator's
    branch), not the feature branch the PR will live on.
  - `$BRANCH_NAME` is out of scope at line 870.

  **Resolution: re-derive both `$BRANCH_PREFIX` and `$PLAN_SLUG` at
  fence-top of the marker-write fence (831-875).** Round 2 empirical
  audit (R-5-1 BLOCKING) confirmed both vars are OUT OF SCOPE at the
  write site — `BRANCH_PREFIX` was defined in fence 147-157 and
  `PLAN_SLUG` in fences 250-262 and 425-441 (all disjoint from fence
  831-875). Textual precedence in SKILL.md is NOT runtime scope:
  separate fenced bash blocks are separate Bash tool invocations
  (separate shell sessions). Inserting `"${BRANCH_PREFIX}${PLAN_SLUG}"`
  naively into the printf would expand to the empty string and write
  `branch:` (empty value) — the same defect class R-4-7 fixed for
  `$LAND_OUTCOME`. This is exactly the "Resolve config-derived vars
  at fence-top" rule articulated at `skills/run-plan/SKILL.md:1326-1328`.

  Concretely: insert the BRANCH_PREFIX-resolution block AND the
  PLAN_SLUG computation immediately AFTER the existing
  `. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"`
  line at fence-top (currently `skills/run-plan/SKILL.md:832`) and
  BEFORE the `BOOKKEEPING_ROOT="$CLAUDE_PROJECT_DIR"` line (currently
  :837). The block to insert:
  ```bash
  # Re-derive BRANCH_PREFIX and PLAN_SLUG at fence-top (R-5-1):
  # both were set in earlier disjoint fences (BRANCH_PREFIX@149-157,
  # PLAN_SLUG@425-441) and do NOT survive cross-fence per
  # SKILL.md:1326-1328 ("Resolve config-derived vars at fence-top").
  BRANCH_PREFIX="feat/"
  if [ -f "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json" ]; then
    CONFIG_CONTENT=$(cat "$CLAUDE_PROJECT_DIR/.claude/zskills-config.json")
    # ([^"]*) allows empty string match -- empty prefix means no prefix
    if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      BRANCH_PREFIX="${BASH_REMATCH[1]}"
    fi
  fi
  PLAN_SLUG=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
  ```
  (`$PLAN_FILE` IS already presumed in scope at the marker-write fence
  — line 847 already references `"$PLAN_FILE"` in the start-marker
  printf, so it's model-substituted at emission consistent with the
  other model-substituted vars at this site.)

  Then inside the `if [ "$LANDING_MODE" = "pr" ]; then` block (before
  the printf), construct:
  ```bash
  BRANCH_NAME_FOR_MARKER="${BRANCH_PREFIX}${PLAN_SLUG}"
  ```
  Then pass `"$BRANCH_NAME_FOR_MARKER"` as the new printf arg. This
  matches the deterministic `BRANCH_NAME="${BRANCH_PREFIX}${PLAN_SLUG}"`
  construction at line 1263, ensuring the marker's `branch:` value is
  identical to what Phase 2's worktree-creation step will assign — the
  value the hook's STOP-message script will compare against the
  current HEAD inside the feature-branch worktree.

  **Why fence-top re-derivation, not env-export (rejected alternative).**
  Round 2 considered `export BRANCH_PREFIX` / `export PLAN_SLUG` at the
  definition sites (fences 147-157 and 425-441) to propagate via env. We
  rejected this because (a) it requires modifying THREE fences instead
  of one for a single feature, (b) the env-survival contract across
  separate Bash tool invocations is not explicitly guaranteed by the
  Claude Code harness (`$ZSKILLS_PIPELINE_ID` survives because it's
  written by parent skills via the Skill tool's env, not because bash
  fences inherit env across separate invocations), and (c) fence-top
  re-derivation matches the existing convention used at lines 254-256
  (Status command's `MAIN_ROOT`/`PROJECT_NAME` re-derivation) and at
  lines 431-433 (Read-authority block's same re-derivation). Small
  duplication, large correctness gain.

  **AC2.9 update:** verify the marker file contains a `branch:` line
  whose value equals `${BRANCH_PREFIX}${PLAN_SLUG}` (NOT `main` and
  NOT the orchestrator's HEAD). Pre-condition: synthesized run with
  `LANDING_MODE=pr` and a known plan file; read the marker after Step 8;
  assert `grep -q "^branch: ${BRANCH_PREFIX}${PLAN_SLUG}$"`.
- [ ] **`/run-plan` modes/pr.md caller-loop — add explicit-finalize
  for `requires.land-pr.<id>` (DA-3-4 fix).** /run-plan's caller-loop
  ends at the `# === END CANONICAL /land-pr CALLER LOOP ===` marker
  in `skills/run-plan/modes/pr.md` (currently line 542) without
  removing the requires marker. **Same-fence requirement:** the new
  cleanup MUST be inserted INSIDE the same `` ```bash ... ``` `` fence
  as the caller-loop (the fence opens at line 291 `` ```bash `` and
  closes at line 543 `` ``` ``), AFTER the `# === END CANONICAL ===`
  line (542) and BEFORE the closing triple-backtick (543). Do NOT
  start a new fence — `$MAIN_ROOT`, `$PIPELINE_ID`, `$TRACKING_ID`
  must be in scope at the rm site.

  **Variable-scope precondition (R-5-10 — tightened):** `$MAIN_ROOT`,
  `$PIPELINE_ID`, `$TRACKING_ID` ARE in scope at the cleanup site —
  verified empirically by fence-map: `awk '/^[[:space:]]*```bash$/...'
  skills/run-plan/modes/pr.md` shows fence 291-543 contains the
  entire caller-loop AND the explicit-finalize cleanup-site (END
  CANONICAL at line 542, closing ``` at 543). The fence-top at line
  291 sets these vars (verified by reading the fence). Same-fence
  guarantees survival per R-4-7.

  Therefore, do NOT re-source `zskills-resolve-config.sh` at the
  cleanup site (the conditional hedge previously in the plan was
  unnecessary and created drift opportunity). Insert the cleanup
  inline:
  ```bash
  # Cleanup transient requires marker (explicit-finalize per
  # docs/plans/LAND_PR_BYPASS_HARDENING.md D2/D8). $MAIN_ROOT,
  # $PIPELINE_ID, $TRACKING_ID are in scope (same-fence as
  # fence-top at line 291).
  rm -f "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.$TRACKING_ID"
  ```

  /run-plan does NOT need a `fulfilled.run-plan.<id>` finalize because
  it ALREADY writes `fulfilled.run-plan.<id> status: started` at Phase
  1 Step 8 (anchor: `printf 'skill: run-plan\nid: %s\nplan: %s\nphase: %s\nstatus: started\ndate: %s\n'`,
  currently `skills/run-plan/SKILL.md:846-848`) and is presumed
  complete at end of run-plan flow — that lifecycle is pre-existing
  and out of scope.

- [ ] **`/land-pr` SKILL.md:533 — modify printf to add `branch:` field**
  (specified in Phase 1 D&C). Format-string change + one new printf
  arg.

- [ ] **PIPELINE_ID export discipline.** Every caller exports
  `ZSKILLS_PIPELINE_ID` BEFORE invoking `/land-pr` via the Skill tool.
  `/land-pr` Step 8b at `SKILL.md:529` already reads it. Pre-existing
  contract; ensure all 5 callers honor it.

### Design & Constraints

- **Marker shape mirrors `/run-plan` SKILL.md's `requires.land-pr.<id>`
  write** (currently at lines 870-874, anchor: the `printf 'skill:
  land-pr\nparent: run-plan\n...'` block) exactly:
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
  in `/commit pr`, `/do pr`, `/quickfix`, `/run-plan modes/pr.md`,
  AND per-issue in `/fix-issues pr` — regardless of LAND_OUTCOME
  (verified by simulating each STATUS arm: merged, pr-ready,
  rebase-conflict). All 5 callers in scope.
- [ ] AC2.6: Explicit-finalize block in each new caller (commit, do,
  fix-issues) rewrites `fulfilled.<skill>.<id>` to:
  - `status: complete` when LAND_OUTCOME ∈ {merged, created, pr-ready}
    (R-5-7: `monitored` dropped — never assigned by source path; the
    outer `monitored` STATUS arm falls through to inner CI_STATUS;
    `pr-ready` includes the inner `unknown`/`*` settle paths per R-4-6
    / DA-4-2 fix — these are success-equivalent, not failures)
  - `status: failed` when LAND_OUTCOME ∈ {rebase-conflict, push-failed, create-failed, merge-failed, monitor-failed, rebase-failed, pr-ci-failing}
  - `status: cancelled` when CANCELLED=1.
- [ ] AC2.7: End-to-end `/do pr` auto-mode invocation produces:
  `fulfilled.do.$SLUG status: complete` + `fulfilled.land-pr.$SLUG
  status: complete` (via /land-pr Step 8b on row-6 merge).
- [ ] AC2.8 (regression): `/quickfix`'s pre-existing
  `fulfilled.quickfix.$SLUG` shape (status fields, finalize_marker
  behavior) is byte-identical pre- and post-this-plan.
- [ ] AC2.9 (DA-2-2 + R-4-2 + R-5-1 + R-5-9 + DA-5-3): `/run-plan`'s
  `requires.land-pr.<id>` write inside Phase 1 Step 8's tracking fence
  (anchor: the `printf 'skill: land-pr\nparent: run-plan\nid: %s\nbranch: %s\ndate: %s\n'`
  block guarded by `if [ "$LANDING_MODE" = "pr" ]; then`, currently
  `skills/run-plan/SKILL.md:870-874`) now includes a `branch:` field
  AND derives the branch name from `${BRANCH_PREFIX}${PLAN_SLUG}`
  (NOT from `git symbolic-ref --short HEAD` and NOT from `$BRANCH_NAME`
  which is out of scope at the write site). Both `BRANCH_PREFIX` and
  `PLAN_SLUG` are re-derived at fence-top of the marker-write fence
  (831-875) per R-5-1 fix; the construction MUST appear AFTER the
  re-derivation block AND BEFORE the printf.

  **Behavioral assert — reproducible script (R-5-9 — replaces prose-only
  recipe; DA-5-3 — config-derived parity rather than hard-coded literal):**
  ```bash
  AC29_ROOT=$(mktemp -d)
  cd "$AC29_ROOT"
  mkdir -p .claude/skills/update-zskills/scripts plans
  # Synthesize a minimal zskills-config with a non-default branch_prefix
  # so the assert is sensitive to actual config-driven behavior.
  cat > .claude/zskills-config.json <<'CFG'
  {"branch_prefix": "ftest/"}
  CFG
  # Provide a stub zskills-resolve-config.sh (the fence sources it):
  cat > .claude/skills/update-zskills/scripts/zskills-resolve-config.sh <<'STUB'
  : ${TRACKING_ID:?}; : ${PLAN_FILE:?}; : ${LANDING_MODE:?}
  STUB
  PLAN_FILE="plans/FOO_BAR.md"
  echo -e "---\nstatus: planning\n---\n# FOO_BAR" > "$PLAN_FILE"
  export CLAUDE_PROJECT_DIR="$AC29_ROOT" TRACKING_ID="foo-bar" \
    PHASE="1" LANDING_MODE="pr" PR_WORKTREE_PATH="" TIMEZONE="UTC"
  # Execute the fence's bash content (with R-5-1 in-fence derivation):
  # ... run the bash block from skills/run-plan/SKILL.md fence 831-875
  # verbatim against the test root ...
  # Then assert:
  grep -q '^branch: ftest/foo-bar$' \
    "$AC29_ROOT/.zskills/tracking/run-plan.foo-bar/requires.land-pr.foo-bar"
  ```
  The assert reads the marker's `branch:` line and expects
  `ftest/foo-bar` (NOT hard-coded `feat/foo-bar`) — derived from the
  test config's `branch_prefix: ftest/` value times the plan slug.
  Failure modes the assert catches: (a) BRANCH_PREFIX unset at write
  site → `branch:` empty (R-5-1 defect); (b) PLAN_SLUG unset →
  `branch: ftest/` (also R-5-1 defect); (c) printf format-string typo
  glues `branch:` to `date:` (DA-5-9 concern — the line-anchored
  `^branch:` regex catches malformed shape).
- [ ] AC2.10: Synthesizing a failure mid-caller-loop (e.g., STATUS=push-failed
  break path) followed by explicit-finalize → `fulfilled.<skill>.<id>`
  ends as `status: failed`, NOT `complete` (DA-2-1 fix verification).
- [ ] AC2.11 (R-4-6 / DA-4-2): Synthesizing CI_STATUS=unknown OR an
  unrecognized CI_STATUS value (catch-all `*` arm) → loop breaks at the
  "settle at pr-ready" arm → `LAND_OUTCOME=pr-ready` → explicit-finalize
  stamps `fulfilled.<skill>.<id>` as `status: complete`, NOT `failed`.
  Negative-test the regression: if implementer forgets the `unknown`/`*`
  arms, LAND_OUTCOME stays default `unknown` and FINAL=failed — assert
  catches this.

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
  - **Pre-flight (per Residual Risk #7):** run
    `grep -nE 'fulfilled\.(land-pr|commit|do|fix-issues|quickfix)\.\*' skills/update-zskills/scripts/clear-tracking.sh`.
    If all five families already appear in the preserve arm (Wave 1
    landed first), skip this sub-bullet — record "no-op (Wave 1
    landed first)" in the implementation log.
  - Otherwise, edit `skills/update-zskills/scripts/clear-tracking.sh`
    around lines 46-57 (anchor: the `while IFS= read -r f; do`
    classification loop's `case "$base" in` block) to extend the
    existing `fulfilled.run-plan.*)` preserve arm:
    ```bash
    case "$base" in
      fulfilled.run-plan.*|fulfilled.land-pr.*|fulfilled.commit.*|fulfilled.do.*|fulfilled.fix-issues.*|fulfilled.quickfix.*)
        preserve_count=$((preserve_count+1)) ;;
      fulfilled.verify-changes.*) c_verify=$((c_verify+1)) ;;
      fulfilled.draft-plan.*)     c_draft=$((c_draft+1)) ;;
      fulfilled.refine-plan.*)    c_refine=$((c_refine+1)) ;;
      requires.*)                 c_requires=$((c_requires+1)) ;;
      step.*|phasestep.*)         c_step=$((c_step+1)) ;;
      verify-pending-attempts.*)  c_vpa=$((c_vpa+1)) ;;
      *)                          c_other=$((c_other+1)) ;;
    esac
    ```
    Also update the `clear_count` arithmetic (line 60) if the
    classification counters change shape (they do NOT in the above
    patch — same counter names preserved). And the verbose-output
    `printf` block (lines 102-113) only displays counters that exist;
    since no counters were renamed, no display changes needed beyond
    optionally updating the preserve-display line at line 104 to
    reflect the new family list (purely cosmetic).
  - **The residual-count assertion at `clear-tracking.sh:150-157` does
    NOT need modification** — verified empirically by reading the
    source: it enumerates `requires.*`, `step.*`, `phasestep.*`,
    `fulfilled.verify-changes.*`, `fulfilled.draft-plan.*`,
    `fulfilled.refine-plan.*`, `verify-pending-attempts.*`. None of
    the new families being added to the preserve arm appear in the
    assertion's `-name` enumeration, so adding them to preserve does
    NOT break the assertion. D9 was correct on this point; the
    previous Phase 3 work item bullet asking to "remove [families]
    from the residual-class enumeration" was a contradiction with D9
    and is REMOVED per R-4-11. **Do NOT edit lines 150-157.**
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
- [ ] AC3.5: `bash skills/update-zskills/scripts/clear-tracking.sh`
  residual assertion (lines 150-157, UNCHANGED per R-4-11 / D9) returns
  0 after a synthesized session — the new families (`fulfilled.land-pr.*`,
  `fulfilled.commit.*`, etc.) are now preserved by the extended arm and
  are NOT in the residual-class `-name` enumeration, so the assertion
  passes naturally.
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
  - **Fence-survival assert (R-4-7 / DA-4-4 + R-5-11 indentation
    tolerance + DA-5-4 counter-assert):** the `sed -i "s/^status:
    started$/status:` line for each caller MUST appear BEFORE the
    closing ` ``` ` of the caller-loop's bash fence.
    Procedure:
    1. Locate the line number of `# === END CANONICAL /land-pr CALLER
       LOOP ===` (use `grep -nF` — substring match — to handle the
       fix-issues case where the anchor is 2-space indented inside a
       per-issue loop wrapper).
    2. Locate the line number of the NEXT closing fence delimiter
       AFTER that anchor. Use `grep -nE "^[[:space:]]*\`\`\`$"` (R-5-11:
       allow leading whitespace — the SKILL.md:875 closing fence in
       /run-plan SKILL.md is 3-space indented inside a numbered-list
       bullet; current callers all use unindented closing fences but
       a future indented case must not silently slip through).
    3. Positive assert: BOTH the `sed -i "s/^status: started$/status:`
       line AND the `rm -f .*requires.land-pr.` line are BETWEEN those
       two line numbers. If the `sed`/`rm` lines appear AFTER the
       closing triple-backtick, the assert FAILS (the finalize was
       placed in a new fence — `$LAND_OUTCOME` would be unset there).
    4. **Counter-assert (DA-5-4):** locate the line AFTER the closing
       ``` of the caller-loop fence (i.e., line N+1 where N is the
       closing-``` line); grep from there to EOF for
       `sed -i "s/^status: started$/status:` AND
       `rm -f .*requires.land-pr.` matching the same caller's marker
       basename — assert ZERO hits. This catches the duplicate-fence
       failure mode where an implementer adds a NEW fence after the
       caller-loop and replicates the finalize there with stale
       (unset) `$LAND_OUTCOME`. The positive assert finds the
       in-fence copy; the counter-assert proves no out-of-fence copy
       exists.
  - `/quickfix`'s pre-existing `fulfilled.quickfix.$SLUG` write at
    `SKILL.md:637` is unchanged (byte-anchor on the surrounding lines).
  - `/quickfix` contains an `rm -f .*requires.land-pr.` line AFTER the
    `# === END CANONICAL ... ===` anchor (the new requires-cleanup).
  - `/run-plan modes/pr.md` contains an `rm -f .*requires.land-pr.`
    line AFTER its `# === END CANONICAL ... ===` anchor (DA-3-4 fix).
  - `/run-plan SKILL.md` `requires.land-pr.<id>` write block (anchor:
    the `printf 'skill: land-pr\nparent: run-plan\nid: %s\nbranch:
    %s\ndate: %s\n'` block guarded by `if [ "$LANDING_MODE" = "pr" ];
    then`; currently lines 870-874) contains `branch:` in its printf
    format string AND derives the branch value from
    `${BRANCH_PREFIX}${PLAN_SLUG}` (NOT from `git symbolic-ref` and
    NOT from `$BRANCH_NAME`) — DA-2-2 + R-3-1 + R-4-2 / DA-4-1.

    **Grep anchors (DA-5-8 — anchor on the NEW variable name introduced
    by this plan to avoid false positives from pre-existing prose
    mentions of `${BRANCH_PREFIX}${PLAN_SLUG}` at lines 1263, 2383,
    2414):**

    Assert 1 — the new variable assignment exists in the fence:
    `grep -nE '^[[:space:]]*BRANCH_NAME_FOR_MARKER=' skills/run-plan/SKILL.md`
    returns at least one hit. The literal variable name
    `BRANCH_NAME_FOR_MARKER=` is introduced by this plan and appears
    nowhere else in the file pre-refactor.

    Assert 2 — fence-top re-derivation lands inside the marker-write
    fence (831-875): identify the closing-``` line number AFTER the
    `printf .* requires.land-pr.\$TRACKING_ID` line; assert the
    `BRANCH_PREFIX="feat/"` line AND the `PLAN_SLUG=$(basename` line
    both appear at line numbers BETWEEN the OPENING ``` of the same
    fence and the `BRANCH_NAME_FOR_MARKER=` line (R-5-1 — fence-top
    re-derivation discipline).

    Assert 3 — textual precedence: the `BRANCH_NAME_FOR_MARKER=` line
    must appear BEFORE the `requires.land-pr.\$TRACKING_ID` printf
    line.
  - `.claude/settings.json` contains the new hook entry.
  - `hooks/block-bypassed-land-pr.sh` is executable AND contains the
    inlined `is_gh_pr_subcommand` function header line.
  - `scripts/land-pr-bypass-message.sh` contains the ASCII anchor
    `STOP: direct gh pr` AND the Pattern 1 anchor `outside a caller
    skill` AND the Pattern 2 anchor `/land-pr invocation appears to have
    errored`.

  Negative asserts (DA-1-5 + DA-1-6 + R-2-5 + R-3-4 + R-4-3 / DA-4-3 +
  R-5-2 / DA-5-2 + R-5-3 / DA-5-1):
  - **Pattern 1 (R-4-3 / DA-4-3 fix — catches bare-line bypass; R-5-2 /
    DA-5-2 tightening — anchored to shell-command position to exclude
    prose false positives; R-5-3 / DA-5-1 scope fix — recursive across
    all `skills/` `.md` sources with `*.md` carve-out for legitimate
    `gh pr create`/`gh pr merge --auto` invocations inside
    `skills/land-pr/scripts/*.sh`).** The regex requires the
    `gh pr (create|merge --auto)` token to sit in a shell-command
    position — either start-of-line (with optional leading whitespace)
    OR after a shell separator (`;`, `&&`, `||`). It excludes comment
    lines (`#` first-non-space char) AND `echo`/`printf` prose
    invocations (per DA-5-2's empirical verification that the prior
    regex matched `echo "running gh pr create now"`):
    ```bash
    grep -rnE "(^|;|\|\||&&)[[:space:]]*gh pr (create|merge[^\`]*--auto)([[:space:]]|$)" \
      skills/ --include='*.md' \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(echo|printf)[[:space:]]'
    ```
    returns zero matches across ALL skills (recursive scope —
    consistent with Patterns 2/3).

    **Scope rationale (R-5-3 / DA-5-1).** AC4.5's threat model is
    "future maintainer pastes `gh pr create` into a caller skill"
    (bypasses #218, #221, #223 all originated in non-land-pr skills).
    Single-file scope (`skills/land-pr/SKILL.md` only) misses the
    primary threat vector. The `--include='*.md'` carve-out excludes
    `skills/land-pr/scripts/*.sh` (the only sanctioned `gh pr create`
    / `gh pr merge --auto` callsites, at
    `skills/land-pr/scripts/pr-push-and-create.sh:142,145,156` and
    `skills/land-pr/scripts/pr-merge.sh:87` — verified by reading
    those files); SKILL.md sources are the bypass-vulnerable surface.

    **Regex rationale (R-5-2 / DA-5-2).** Anchoring on `(^|;|\|\||&&)`
    requires the token to appear in shell-command-position context, not
    inside prose. The trailing `([[:space:]]|$)` requires a space or
    EOL after the verb (excludes `gh pr created.` past-tense prose).
    The two `grep -v` filters strip comments and `echo`/`printf` prose.
    Empirically tested fixtures:

    **Must-match fixtures** (add to Phase 5 test corpus):
    - `gh pr create -B main` (bare)
    - `  gh pr create -B main` (indented)
    - `cd /tmp/wt && gh pr create -B main` (chained via `&&`)
    - `foo; gh pr create -B main` (chained via `;`)
    - `gh pr merge --auto`
    - `gh pr merge --auto --squash --delete-branch` (3-flag)
    - `gh pr merge --delete-branch --squash --auto` (auto at end)

    **Must-NOT-match fixtures**:
    - `` `gh pr create` again. `` (backtick-wrapped prose; line 601 case)
    - `# gh pr create -B main` (comment line)
    - `   # gh pr create` (indented comment)
    - `echo gh pr create` (echo prose; DA-5-2)
    - `echo "running gh pr create now"` (echo with double-quotes; DA-5-2)
    - `printf 'gh pr create'` (printf prose)
    - `But avoid gh pr create directly per CLAUDE.md.` (English prose,
      no shell separator)
    - `do not use gh pr create` (English prose)
    - `foo gh pr create bar` (no shell separator before token)
    - `some_cmd  # avoids gh pr create` (trailing-comment prose;
      caught by `echo|printf` filter? NO — caught because the comment-
      strip would not strip this line. Verify: this line does NOT
      start with `#`, so first `grep -v` does not strip; but the
      regex itself requires shell-separator precedence — `# avoids`
      is text not a shell separator — so primary regex does not
      match. Verified empirically.)
    - `gh pr edit --body-file ...`
    - `gh pr merge` (bare, no `--auto`)
    - `gh pr --help`
    - `bash -c 'gh pr create'` (Pattern 2 catches this; Pattern 1
      intentionally does NOT — bash -c wrapping is a separate
      threat class)

    Implementer-agent runs the must-match/must-NOT-match assertions
    against fixture files (NOT against live skill source — the live
    source must produce zero matches after Pattern 1 is corrected).
    **Empirical verification gate:** before committing the assert,
    the implementer MUST run the recursive pipeline against current
    `skills/` and confirm zero matches (verified by refiner Round 2:
    zero matches against post-Round-1 source).
  - **Pattern 2** (idiomatic `bash -c` / `sh -c` wrapper — backstop for
    `bash -c '...gh pr create...'`):
    ```bash
    grep -nrE "(bash|sh)[[:space:]]+-c[[:space:]]*['\"][^'\"]*gh pr (create|merge[^'\"]*--auto)" skills/
    ```
    returns zero matches across ALL skills.
  - **Pattern 3** (`eval` wrapper):
    ```bash
    grep -nrE "eval[[:space:]]+['\"][^'\"]*gh pr (create|merge[^'\"]*--auto)" skills/
    ```
    returns zero matches.
  - **Verified against current source:** these patterns return zero
    matches today (verified by running the corrected Pattern 1 against
    `skills/land-pr/SKILL.md` — only line 601's backtick-wrapped prose
    needs to be tolerated, and the regex correctly excludes it).
    Implementer must re-verify before committing the assert (so the
    assert doesn't immediately fail on a pre-existing legitimate use).
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
- [ ] AC4.5: Adding any of the following to any skill source →
  conformance negative-assert FAILS (DA-4-7 coverage expansion):
  - `bash -c 'gh pr create'` (Pattern 2)
  - `sh -c 'gh pr create'` (Pattern 2 variant)
  - `eval 'gh pr create'` (Pattern 3)
  - `cd /tmp/wt && gh pr create -B main` (Pattern 1 chained — start-of-
    line + chained shell ops; the corrected R-4-3 regex catches this)
  - `gh pr create -B main` bare at start-of-line (Pattern 1 — DA-4-3
    case)
  Each is tested by inserting the line into a bash fence in a known
  skill, running the conformance script, and asserting FAIL; then
  reverting and asserting PASS.
- [ ] AC4.6: Adding an UNQUOTED (no backticks) `gh pr create` line to
  a `skills/land-pr/SKILL.md` bash fence → conformance negative-assert
  FAILS (negative test). The current line 601
  (` `gh pr create` again. The script does NOT call \`gh pr edit\``
  — backtick-wrapped prose) MUST NOT trigger the assert (regression
  smoke). Test by (a) adding a fixture line `gh pr create -B main`
  inside an existing bash fence → assert FAILS; (b) reverting →
  assert PASSES.

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
  pattern). Test matrix (20 cases — R-4-14):
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
- [ ] AC5.6 (DA-5-9 — marker-shape integration smoke): after exercising
  the synthesized `/run-plan auto` and `/commit pr` invocations from
  AC2.1 / AC2.9, parse each generated `requires.land-pr.<id>` marker
  line-by-line and assert (a) `skill:`, `parent:`, `id:`, `branch:`,
  `date:` each appear on a separate line (no glued fields); (b) the
  `branch:` value matches `^[a-zA-Z0-9./_-]+$` (no shell-metacharacters
  or empty value); (c) the `date:` value parses as ISO-8601 (e.g.,
  `date -d "$(grep '^date:' marker | cut -d' ' -f2-)" >/dev/null 2>&1`).
  Catches printf format-string typos (missing `\n` between fields)
  and any expansion-failure that produces empty `branch:`. Smoke
  must run AFTER AC2.1-2.9 produce live markers.

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
    `requires.land-pr.<id>` write (anchor: the `printf 'skill:
    land-pr\nparent: run-plan\n...'` block in Phase 1 Step 8;
    currently lines 870-874) per DA-2-2 / R-4-2 fix.
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
- **Cascade rule (R-4-15 — documented for future readers).** Any edit
  under `skills/<owner>/...` — including `scripts/`, `references/`,
  `modes/`, fixtures, install manifests — triggers a `metadata.version`
  bump on the parent `<owner>/SKILL.md`. This plan's 7-skill bump
  list is the application of this rule across all touched subtrees
  (e.g., `modes/pr.md` edits → parent SKILL.md bump even though
  SKILL.md content didn't change; `scripts/clear-tracking.sh` edits →
  parent `update-zskills/SKILL.md` bump). Verifier should reapply
  this rule independently before approving Phase 6.
- **Non-cascade scope (DA-5-7 clarification).** Edits to
  `hooks/_lib/*.sh` (this plan touches `hooks/_lib/git-tokenwalk.sh`
  to add `is_gh_pr_subcommand`) and top-level `scripts/*.sh` (this
  plan adds `scripts/land-pr-bypass-message.sh`) do NOT trigger any
  skill `metadata.version` bump — these locations are outside the
  per-skill cascade scope by design. They're versioned via the
  repo-level zskills tag only. Drift between source `hooks/_lib/`
  and inlined hook copies is caught by `tests/test-hook-helper-drift.sh`
  (extended to 4 hooks per AC4.4). Drift between source
  `scripts/land-pr-bypass-message.sh` and any consumer copy is
  not relevant (consumers re-mirror on `/update-zskills`).

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
4. **Stale `requires.land-pr.<id>` across sessions (DA-4-11
   refinement)** — the explicit-finalize at end of each caller's bash
   flow removes the marker, but if the caller's last bash fence didn't
   run (Claude session crashed mid-flow) OR if a /quickfix mid-exit
   path orphaned the marker (Residual Risk #8), the marker persists.
   Next session's hook would emit Pattern 2 wording (mid-flight)
   incorrectly on a fraction of legitimate `gh pr` typing attempts.
   Recovery: user runs
   `bash skills/update-zskills/scripts/clear-tracking.sh` to clear
   all `requires.*` markers (NOT preserved per D9 — they're transient
   by design). The Pattern 2 STOP message body MUST include a hint to
   this effect: append the sentence "If you believe this is a stale
   marker from a prior crashed session, run
   `bash skills/update-zskills/scripts/clear-tracking.sh` to clear
   and retry." to Pattern 2 (in addition to the existing recovery
   guidance). Pattern 1 does NOT need this hint (Pattern 1 fires when
   NO matching marker exists, so the stale-marker case doesn't apply).
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
   already there, no-op." Phase 3 implementer MUST run
   `grep -nE 'fulfilled\.(land-pr|commit|do|fix-issues|quickfix)\.\*' skills/update-zskills/scripts/clear-tracking.sh`
   as a pre-flight check before applying the Phase 3 sub-bullet; if all
   five families are present, mark Phase 3 sub-bullet "no-op (Wave 1
   landed first)" and proceed.
8. **`/quickfix` mid-exit orphan markers (DA-4-8 / R-4-9 acknowledged
   risk).** `/quickfix` has 11+ `exit 1/2/5/6` paths between fence
   631-678 (`requires.land-pr.$SLUG` marker-setup) and the line 1244
   explicit-finalize site. Any of these exits leaves the marker
   orphaned. Recovery: (a) `bash skills/update-zskills/scripts/clear-tracking.sh`
   clears `requires.*` markers (they are NOT preserved per D9 — transient
   by design); (b) next /quickfix session's marker overwrite (same
   `$SLUG` produces same path). User-visible impact: hook may emit
   Pattern 2 STOP message ("/land-pr invocation appears to have
   errored mid-flight") on direct `gh pr create` attempts after a
   crashed /quickfix run, until the marker is cleared. This is bounded
   noise, not silent correctness loss. Mitigation NOT shipped because
   retrofitting 11+ exits with inline cleanup risks introducing bugs
   in /quickfix's tested flow; cost-benefit favors documenting +
   accepting. Tracked as informational (not a blocker for #228 Part B).
   Orthogonal to the /quickfix `finalize_marker` trap bug (D7 / #241),
   which is also acknowledged-deferred.

## Drift Log

(Updated post-implementation by /run-plan / /refine-plan.)

| Date | Change | Reason |
|------|--------|--------|
| 2026-05-12 | /refine-plan R1: replaced `git symbolic-ref --short HEAD` with `${BRANCH_PREFIX}${PLAN_SLUG}` at /run-plan SKILL.md:873 marker-write site. | R-4-2 / DA-4-1: Phase 1 Step 8 runs BEFORE worktree cd; symbolic-ref returned orchestrator branch (typically `main`) instead of feature branch — broke Pattern-2 branch-correlation. |
| 2026-05-12 | /refine-plan R1: revised AC4.5 Pattern 1 regex to allow start-of-line bare `gh pr create`. | R-4-3 / DA-4-3: Round 3 regex missed bare bypass case. |
| 2026-05-12 | /refine-plan R1: added `unknown` and `*` arms to LAND_OUTCOME mapping → `pr-ready` → `FINAL=complete`. | R-4-6 / DA-4-2: incomplete mapping silently stamped success as `failed`. |
| 2026-05-12 | /refine-plan R1: added Phase 2 "Same-fence requirement" clause + Phase 4 positive conformance assert for `sed -i` placement. | R-4-7 / DA-4-4: variable-survival of `$LAND_OUTCOME` requires same-fence placement; prior prose ambiguous. |
| 2026-05-12 | /refine-plan R1: /quickfix + other callers' cleanup-site re-resolve config explicitly. | DA-4-5: vars defined in tracking-setup fence don't survive to caller-loop fence. |
| 2026-05-12 | /refine-plan R1: accepted /quickfix's 11 mid-exit paths as Residual Risk #8 (orphan-marker rate, recoverable). | DA-4-8: retrofit risk > orphan recovery cost. |
| 2026-05-12 | /refine-plan R1: reconciled D9-vs-Phase-3 contradiction on residual-count assertion. | R-4-11: assertion enumerates classes-to-be-cleared, not preserved — D9 was canonical. |
| 2026-05-12 | /refine-plan R1: removed stale line-number citations (`:851-855` → `:870-873`, etc.); switched to anchor-based citations where possible. | R-4-1 / DA-4-12: post-PR-#239/#240 line-number drift. |
| 2026-05-12 | /refine-plan R2: R-5-1 BLOCKER fix — added fence-top re-derivation of `BRANCH_PREFIX` + `PLAN_SLUG` at the marker-write fence. | R-5-1: R1's substitution vars were ALSO in disjoint fences from the write site, recreating the original fence-survival defect class. |
| 2026-05-12 | /refine-plan R2: AC4.5 regex tightened to shell-command-position anchor + 2-step `echo`/`printf` prose-strip pipeline. | R-5-2 / DA-5-2: R1 regex matched `# gh pr create`, `echo gh pr create`, double-quoted prose (false positives). |
| 2026-05-12 | /refine-plan R2: AC4.5 Pattern 1 made recursive across `skills/` with `--include='*.md'` carve-out exempting `skills/land-pr/scripts/`. | R-5-3 / DA-5-1: Pattern 1 was single-file-scoped while threat model is multi-skill. |
| 2026-05-12 | /refine-plan R2: added counter-assert against `sed -i` AFTER caller-loop's closing ```. | DA-5-4: R1's positive assert allowed implementer to write a SECOND `sed -i` in a new fence (variable unset) without tripping. |
| 2026-05-12 | /refine-plan R2: explicit `LAND_OUTCOME=pr-ci-failing` insertion-point spec for fix-cycle-exhausted path. | R-5-4: ambiguous prose for where in nested `if ATTEMPT >= MAX` block the assignment goes. |
| 2026-05-12 | /refine-plan R2: 14 minor consistency + documentation fixes (cancelled-arm cleanup; monitored drop from success-set; AC2.9 config-derived assert; non-cascade scope clarification; etc.) | Round 2 substantive + minor findings. |

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds (orchestrator-judged
max-rounds-reached, post-PR-#238), then /refine-plan with 2 rounds
(post-PR-#238 drift correction + Round-1-fix-introduced-bug correction).
**Convergence:** Orchestrator-judged max-rounds-reached for /refine-plan.
Trend: /draft-plan Round 3 = 4 inline-patched blockers → /refine-plan
Round 1 = 5 blockers FIXED → /refine-plan Round 2 = 1 blocker FIXED
+ 4 substantive + 6 minor (all dispositioned). Diminishing-returns
trajectory pronounced. Plan is shippable.

**Remaining concerns (acknowledged, not blockers):**
- /quickfix's pre-existing trap-on-EXIT bug (DA-3-3 / issue #241) is
  documented but NOT fixed in this plan — separate Wave 1 follow-up.
- /quickfix has 11+ mid-exit paths that can orphan `requires.land-pr.$SLUG`
  markers (Residual Risk #8 — accepted with documented recovery).
- Wave 1's clear-tracking widening is a parallel dependency
  (Residual Risk #7).
- DA-5-6 "SHOULD generate programmatically" is a soft directive
  (verifier judgment call).
- DA-5-4 counter-assert scope is same-skill files only; cross-skill
  duplicate-fence pattern remains speculative.
- All other findings dispositioned.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 12 (R-1-1..12)    | 13 (DA-1-1..13)           | 25/25 (5 no-action; rest fixed; DA-1-7 / DA-1-10 justified-not-fixed) |
| 2     | 13 (R-2-1..13)    | 10 (DA-2-1..10)           | 23/23 (Round 2 refinement complete) |
| 3     | 8 (R-3-1..8)      | 7 (DA-3-1..7, DA-3-8)     | 14/15 (DA-3-3 documented as pre-existing /quickfix bug — defer-fix scope decision) |
| 4 (/refine-plan post-PR-#238) | 18 (R-4-1..18) | 12 (DA-4-1..12) | 28 FIXED + 1 no-action (R-4-17) + 1 ACCEPTED-DOCUMENTED (DA-4-8 via Residual Risk #8) = 30 dispositioned (DA-5-10 wording fix — "dispositioned" not "resolved" since accepted-risk is not code-level fixed) |
| 5 (/refine-plan Round 2) | 11 (R-5-1..11) | 10 (DA-5-1..10) | 1 BLOCKING (R-5-1 fence-survival sister-site) + 4 substantive + 6 minor (Round 2 refiner) = 21 findings; all 11 R-5-* fixed; all 10 DA-5-* fixed/justified per Round 2 disposition table |

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

#### Round 4 — disposition table (/refine-plan post-PR-#238 drift)

| Finding | Verification | Disposition |
|---------|--------------|-------------|
| R-4-1 (stale line refs to /run-plan SKILL.md throughout plan) | Verified — actual write at lines 870-874 (commits bbf9742, c29b7a9 inserted code above) | **Fixed** — all 851-855 / 825 / 826-829 refs re-anchored to printf-block anchors with currently-line-N annotations |
| R-4-2 BLOCKING (`git symbolic-ref --short HEAD` at write site returns wrong branch) | Verified — Phase 1 Step 8 runs in orchestrator CWD (= main repo); HEAD = `main`, not feature branch | **Fixed** — derive branch from `${BRANCH_PREFIX}${PLAN_SLUG}` (both in scope: BRANCH_PREFIX:149, PLAN_SLUG:428); AC2.9 strengthened with behavioral assert |
| R-4-3 BLOCKING (AC4.5 Pattern 1 regex misses bare `gh pr create`) | Verified empirically via /tmp/regex-test.txt | **Fixed** — new regex `(^[[:space:]]*\|[^\`])gh pr (create\|merge[^\`]*--auto)([^\`]\|$)` + comment-strip pipeline; must-match and must-NOT-match fixtures specified |
| R-4-4 (50-char threshold arbitrary) | Verified — static fallback ~250 chars, no legitimate dynamic message < 67 chars | **Fixed** — "empty after whitespace-strip" replaces "shorter than 50 chars" |
| R-4-5 (AC1.7 missing 3+ flag permutations) | Verified | **Fixed** — AC1.7 extended with 9 flag-order permutations including `--delete-branch --squash --auto` |
| R-4-6 BLOCKING (LAND_OUTCOME mapping omits CI_STATUS=unknown and `*`) | Verified at `skills/commit/modes/pr.md:195-200` — both arms break with "settle at pr-ready" comment | **Fixed** — mapping extended; `unknown → pr-ready`, `*) → pr-ready`; AC2.11 added; AC2.6 updated |
| R-4-7 BLOCKING (fence-survival of $LAND_OUTCOME unspecified) | Verified — all 5 callers have single-fence caller-loops; vars don't survive across fences | **Fixed** — "Same-fence requirement" section added to Phase 2 marker-lifecycle; Phase 4 fence-survival assert added (sed/rm lines must be inside caller-loop fence) |
| R-4-8 (stale `END CANONICAL` line refs in /run-plan modes/pr.md) | Verified — END CANONICAL at line 542 | **Fixed** — re-anchored on `# === END CANONICAL ===` marker not line numbers |
| R-4-9 (inline cleanup before exit-1 underspecified, especially /quickfix 11 exits) | Verified | **Fixed** — split into per-caller strategy: commit/do/fix-issues INLINE; /quickfix ACCEPT-RISK + Residual Risk #8 |
| R-4-10 (AC2.5 omits /run-plan) | Verified — Work Items add /run-plan finalize but AC2.5 wording predated | **Fixed** — AC2.5 enumeration expanded to all 5 callers |
| R-4-11 (D9 vs Phase 3 Work Item contradiction on residual assertion edit) | Verified by reading `clear-tracking.sh:150-157` — assertion lists classes that should be CLEARED, not preserved; D9 is correct | **Fixed** — Phase 3 Work Item's "edit residual-count assertion" sub-bullet REMOVED; explicit "Do NOT edit lines 150-157" note added |
| R-4-12 (AC4.5 same regex flaw as R-4-3) | Duplicate of R-4-3 | **Fixed** — same fix |
| R-4-13 (AC4.6 ambiguity — "any bash fence" vs backtick-prose) | Verified | **Fixed** — AC4.6 reworded with UNQUOTED requirement + regression-smoke against line 601 |
| R-4-14 (numeric drift "16 cases" vs C1-C20) | Verified | **Fixed** — Phase 5 work item updated to "20 cases" |
| R-4-15 (cascade-rule note missing in Phase 6) | Judgment | **Fixed** — cascade-rule note added to Phase 6 D&C |
| R-4-16 (Wave 1 pre-flight grep guidance) | Judgment | **Fixed** — Phase 3 Work Item pre-flight grep added; Residual Risk #7 expanded with explicit grep |
| R-4-17 (`/quickfix unchanged` prose precision) | Verified clear | **No action** |
| R-4-18 (D7 hedge weak — "/quickfix partial-AC" ambiguous) | Judgment | **Fixed** — D7 strengthened to "structurally unmet"; consumer-side caveat added |
| DA-4-1 BLOCKING (= R-4-2 — branch substitution returns wrong branch) | Verified | **Fixed** — same as R-4-2 |
| DA-4-2 BLOCKING (= R-4-6 — LAND_OUTCOME unknown/* missing) | Verified | **Fixed** — same as R-4-6 |
| DA-4-3 BLOCKING (= R-4-3 — regex misses bare gh pr create) | Verified empirically | **Fixed** — same as R-4-3 |
| DA-4-4 BLOCKING (= R-4-7 — fence-survival unspecified) | Verified | **Fixed** — same as R-4-7 |
| DA-4-5 BLOCKING (/quickfix $TRACK_DIR & $SLUG out of scope at line 1244) | Verified — fence 631-678 ≠ fence 1071-1245; vars don't survive | **Fixed** — /quickfix Work Item now re-resolves config + reconstructs PIPELINE_ID + SLUG at cleanup site |
| DA-4-6 (`continue` semantics on fail-arm) | Verified at `commit/modes/pr.md:145-194` | **Fixed** — explicit `continue`-semantics paragraph added to marker-lifecycle section |
| DA-4-7 (regex doesn't catch &&-chained or piped variants) | Verified | **Fixed** — corrected Pattern 1 (R-4-3) catches `cd && gh pr create`; AC4.5 expanded with explicit fixtures |
| DA-4-8 (/quickfix 11 exit-1 paths unenforceable) | Verified — 11 hits via grep | **ACCEPTED-DOCUMENTED** — Residual Risk #8 added; commit/do/fix-issues use INLINE strategy; /quickfix accepts orphan-marker risk with explicit recovery via clear-tracking |
| DA-4-9 (= R-4-18 — D7 hedge tightening) | Judgment | **Fixed** — same as R-4-18 |
| DA-4-10 (Phase 3 residual-assertion verifiability) | Judgment | **Fixed** — D9 now quotes the actual residual-block source so claim is self-contained |
| DA-4-11 (Residual Risk #4 understates orphan rate) | Verified | **Fixed** — Risk #4 expanded; Pattern 2 STOP message now includes `clear-tracking.sh` hint |
| DA-4-12 (= R-4-1 / R-4-2 — AC4 stale 851-855 line range) | Verified | **Fixed** — AC4 positive-assert re-anchored on printf-block, with grep anchor for `${BRANCH_PREFIX}${PLAN_SLUG}` construction |

#### Round 5 — disposition table (/refine-plan Round 2 — adversarial against Round 1 fixes)

| Finding | Verification | Disposition |
|---------|--------------|-------------|
| R-5-1 BLOCKING (Round 1's `${BRANCH_PREFIX}${PLAN_SLUG}` substitution recreates fence-survival defect at sister site) | Verified empirically — BRANCH_PREFIX@149 in fence 147-157; PLAN_SLUG@428 in fence 425-441; write site @873 in fence ~825-906; all disjoint | **Fixed** — added fence-top re-derivation of both vars at marker-write fence; matches the same `:1326-1328` convention used elsewhere |
| R-5-2 (Pattern 1 regex matches `# gh pr create` + `echo gh pr create` — false positives) | Verified empirically via grep | **Fixed** — regex tightened to shell-command-position anchor; 2-step `echo`/`printf` prose-strip pipeline |
| R-5-3 (Pattern 1 single-file vs Patterns 2/3 recursive — scope mismatch) | Verified | **Fixed** — Pattern 1 made recursive across `skills/` with `--include='*.md'` + `skills/land-pr/scripts/` carve-out |
| R-5-4 (LAND_OUTCOME=pr-ci-failing insertion point underspecified) | Verified at `skills/commit/modes/pr.md:145-148` | **Fixed** — exact insertion-point spec for nested-`if` `fail` arm |
| R-5-5 (/quickfix `$SLUG` fallback is circular — `$BRANCH` also out-of-fence) | Verified | **Fixed** — glob-based cleanup replaces fragile re-derivation; covered by Residual Risk #8 |
| R-5-6 — R-5-11 (minor consistency: cancelled-arm dead code, monitored success-set, unknown overload, AC2.9 recipe, hedge wording, indented fence regex) | Mix of verified + judgment | **Fixed** — 6 minor corrections applied |
| DA-5-1 (= R-5-3) | Verified — duplicate | **Fixed** — same as R-5-3 |
| DA-5-2 (= R-5-2 — regex prose false-positive) | Verified empirically | **Fixed** — same as R-5-2 |
| DA-5-3 (AC2.9 hardcodes `feat/foo-bar`) | Verified | **Fixed** — AC2.9 rewritten as reproducible config-derived script |
| DA-5-4 (fence-survival positive-assert lacks negative counter-assert) | Judgment | **Fixed** — counter-assert added: no `sed -i` AFTER caller-loop's closing ``` |
| DA-5-5 (empty-stderr fallback doesn't handle corrupt non-empty stderr) | Judgment | **Fixed** — sentinel-anchored fallback: requires `STOP: direct gh pr` substring, else use static |
| DA-5-6 (AC1.7 should generate flag-perms programmatically) | Judgment | **Soft directive** — verifier judgment call; AC1.7 expanded to 9 perms but generation left to implementer |
| DA-5-7 (Phase 6 cascade rule silent on `hooks/_lib/` + top-level `scripts/`) | Verified | **Fixed** — non-cascade scope clarified |
| DA-5-8 (AC4 grep-anchor matches pre-existing prose) | Verified | **Fixed** — 3 specific asserts on `BRANCH_NAME_FOR_MARKER=` variable name |
| DA-5-9 (no marker-shape integration smoke for AC2.9) | Judgment | **Fixed** — AC5.6 added |
| DA-5-10 (Round History wording "resolved" vs "dispositioned") | Stylistic | **Fixed** — table wording corrected |
