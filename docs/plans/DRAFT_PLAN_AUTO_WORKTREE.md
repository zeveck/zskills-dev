---
issue: 226
title: /draft-plan auto-worktree + auto-commit (PR-mode projects)
created: 2026-05-12
status: superseded
superseded_by: docs/plans/PREAMBLE_WORKTREE_GATE.md
---

# Plan: /draft-plan auto-worktree + auto-commit (PR-mode projects)

> **SUPERSEDED 2026-05-12** — this plan over-engineered #226 as a /draft-plan-specific
> auto-worktree feature (2000+ lines, 5-condition gate, parent= detection, state
> file, multi-fence Phase 0). The real shape is a shared preamble used by 6
> file-writing skills. See `PREAMBLE_WORKTREE_GATE.md`. PR #244 landed this plan
> as a planning artifact; do NOT implement from this file.

> **Landing mode: PR** -- This plan targets PR-based landing. All phases
> use worktree isolation with a named feature branch.

## Overview

`/draft-plan` today writes a plan file to the current working tree but takes
no responsibility for the surrounding git/worktree state. In a project
configured with `execution.landing: pr` + `execution.main_protected: true`,
a standalone invocation leaves an uncommitted plan file on a branch the user
can't even commit to, forcing a manual "create worktree, copy plan, recommit"
dance — the exact friction that prompted issue #226.

This plan adds two coordinated behaviors to `/draft-plan`: **(A) a new Phase 0
that auto-creates a worktree** (gated to PR-mode + main-protected + standalone +
not-already-in-a-worktree), and **(B) a new Phase 6 step 2.5 that auto-commits
the written plan file** whenever the skill is operating inside a worktree (auto-
created OR pre-existing). The Arguments parser is extended to recognize and
**strip** a new `parent=<name>` delegation token; `/research-and-plan` AND
`/run-plan` are updated to emit that token (so `/run-plan auto`'s plan-refresh
dispatch doesn't trip the gate); a new pure-shell canary exercises the gate
cases; and the existing conformance suite is extended with new assertions to
lock the contract.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — /draft-plan SKILL.md edits (parser + Phase 0 + Phase 6 step 2.5 + report) | ⬚ | | |
| 2 — Parent-skill delegation signal (/research-and-plan + /run-plan) | ⬚ | | |
| 3 — Conformance test additions | ⬚ | | |
| 4 — Canary: pure-shell gate fixture | ⬚ | | |
| 5 — Full verification & manual smoke | ⬚ | | |

---

## Phase 1 — /draft-plan SKILL.md edits (parser + Phase 0 + Phase 6 step 2.5 + report)

### CRITICAL implementer note — Phase 0 chunks MUST merge into a SINGLE bash fence in SKILL.md

The Phase 0 specification below (under "Design & Constraints") presents
its bash logic as **multiple `` ```bash `` chunks for readability** — config
read, delegation detection, `.zskills-tracked` SKIP, TRACKING_ID
derivation, gate+invocation, modernization-seed, state-file write. These
chunks reference each other's variables (`$LANDING_HINT`, `$TOPLEVEL`,
`$MAIN_ROOT`, `$DELEGATED`, `$ALREADY_MANAGED`, `$BRANCH_PREFIX`,
`$IN_WORKTREE`, `$WT_PATH`, `$AUTO_WORKTREE_CREATED`,
`$OUTPUT_FILE_ABS`, `$OUTPUT_FILE_REL`, `$TRACKING_ID`,
`$DRAFT_PLAN_PARENT`) AND share a shell function (`derive_output_paths`).

**When integrating Phase 0 into `skills/draft-plan/SKILL.md`, the
implementer MUST concatenate all Phase 0 bash chunks into a SINGLE
`` ```bash ... ``` `` block.** Splitting them in the source SKILL.md
would re-create the one-shot-fence problem the state-file mechanism is
designed to solve cross-PHASE; this single-fence rule preserves
within-PHASE variable continuity.

- **State file** (`/tmp/zskills-draftplan-state-${TRACKING_ID}.env`)
  carries variables ACROSS phases (Phase 0 → Phase 6).
- **Single Phase 0 bash fence** carries variables WITHIN Phase 0.

Phase 3 includes a conformance assertion that Phase 0 contains **exactly
ONE** `` ```bash ... ``` `` block — see Phase 3 "Phase 0 fence-count
assertion". This is the runtime-correctness contract; conformance enforces it.

### Goal

Make four coordinated edits to `skills/draft-plan/SKILL.md`:

1. Extend the **Arguments parser** (`## Arguments` section) to recognize and
   STRIP a `parent=<name>` token so it never leaks into the description body.
2. Add a new **`## Phase 0 — Worktree setup (conditional auto-create)`** with
   the gate logic, **state-file write**, `create-worktree.sh` invocation,
   exit-code routing, and explicit `OUTPUT_FILE_*` variable conventions.
3. Add a new **Phase 6 step 2.5 — Auto-commit the plan file** with a no-op-aware
   `git add` / `git commit` block that **reads the state file** Phase 0 wrote.
4. Extend the **Phase 6 step 4 "Present the result"** template to surface
   worktree/branch/commit when applicable, and amend the existing step 2 prose
   ("Write the plan file") to reference `$OUTPUT_FILE_ABS`.

Then bump `metadata.version` and regenerate the installed mirror.

### Work Items

- [ ] **Parser edit (`## Arguments` section).** In the existing skill at the
      `## Arguments` heading and the `**Detection:**` enumeration: add a new
      bullet for `parent=<name>` recognition (treat as a non-description
      flag; record and strip from `$ARGUMENTS` before the description boundary
      is computed). Update the argument-hint in frontmatter
      (`argument-hint: "[output FILE] [rounds N] [parent=<name>] <description...>"`).
- [ ] **Parser→bash handoff fence (NEW — closes R-F3).** Before Phase 0's
      first bash fence, add a prose paragraph instructing the orchestrator
      to emit a *parser-output literal* fence as the FIRST bash block of
      Phase 0. The orchestrator-LLM performs the prose-parser pass over
      `$ARGUMENTS` and writes verbatim assignments — see "Parser→bash
      handoff" under Design & Constraints.
- [ ] **Phase 0 insertion.** Insert a new `## Phase 0 — Worktree setup (conditional auto-create)`
      section **between the Pre-check (Existing file) heading and `## Phase 1 — Research`**.
      Structural anchor: the section ends one line above `## Phase 1 — Research`.
      Body must contain: the **parser→bash handoff** prose, the **TRACKING_ID
      derivation**, **OUTPUT_FILE normalization (unconditional)**, the
      **five SKIP conditions** evaluated in order (NEW: 5th condition is
      `.zskills-tracked` presence), the verbatim **`create-worktree.sh`
      invocation** with config-driven `--branch-name`, the **exit-code
      routing table** (rc=0/2 proceed, all others surface and exit) with
      **user-facing recovery prose** for rc=3 and rc=10, the **state-file
      write** that persists `WT_PATH` / `OUTPUT_FILE_ABS` / `OUTPUT_FILE_REL`
      / `TRACKING_ID` / `AUTO_WORKTREE_CREATED` / `IN_WORKTREE` /
      `BRANCH_PREFIX` for downstream fences, the prose instruction telling
      the orchestrator to STOP the skill if the fence exits non-zero, and
      the **post-creation re-pre-check** that re-reads the existing plan
      file from `$OUTPUT_FILE_ABS` on resume (PLUS a `cp` of MAIN's prior
      plan file into the fresh worktree on the rc=0 modernization path).
- [ ] **Phase 6 step 2.5 insertion.** Insert a new bolded sub-step
      `**2.5 Auto-commit the plan file (if in any worktree).**` after the
      step 2 body (`**Write the plan file**`) and before the step 3 heading
      (`**Plan index — do not touch.**`). Body must: (1) source the
      Phase 0 state file at the top; (2) gate on `IN_WORKTREE` from the
      state file (not on cwd-derived `git rev-parse --show-toplevel`);
      (3) commit via `git -C "$WT_PATH"` with the **co-author resolution**,
      **one-liner derivation**, **no-op guard**, and **staged-set defense**.
- [ ] **Phase 6 step 2 amendment.** Edit the existing step 2 body (currently
      "Write the plan file to the output path.") to source the state file
      and reference `$OUTPUT_FILE_ABS` so the orchestrator writes inside the
      worktree when Phase 0 created one. When Phase 0 SKIPPED,
      `$OUTPUT_FILE_ABS` resolves to the main-tree path (behavior unchanged).
- [ ] **Phase 6 step 4 extension.** Extend the "Present the result" prose to
      conditionally include `worktree path`, `branch name`, and `commit SHA`
      when those variables are set; when not set, fall back to today's
      behavior unchanged.
- [ ] **Skill-versioning bump (mandatory).** Run from inside the worktree,
      via subshell-`cd`, so the `block-stale-skill-version.sh` hook sees
      the worktree's index (see "Hook composition with `git -C` from
      foreign cwd" under D&C; closes D-A / R-F12 / D-J):
      ```bash
      ( cd "$WT_PATH" && \
        today=$(TZ=America/New_York date +%Y.%m.%d) && \
        hash=$(bash scripts/skill-content-hash.sh skills/draft-plan) && \
        bash scripts/frontmatter-set.sh skills/draft-plan/SKILL.md metadata.version "$today+$hash" && \
        bash scripts/mirror-skill.sh draft-plan && \
        diff -rq skills/draft-plan .claude/skills/draft-plan )
      ```
      The final `diff -rq` must be silent. The implementation commit
      itself uses the same subshell pattern:
      `( cd "$WT_PATH" && git add ... && git commit ... )`. See
      "Multi-commit version-bump discipline" below — every commit in any
      later phase that re-touches this skill must repeat this dance.

### Design & Constraints

#### Insertion seams (structural anchors, not line numbers)

Line numbers drift the moment Phase 1's first edit lands; anchor by
**adjacent headings/text**:

- **Parser edit:** inside the `## Arguments` section's `**Detection:**`
  enumeration, between the `rounds` bullet and the "Everything else …"
  catchall.
- **Phase 0 insertion:** new top-level `## Phase 0 — Worktree setup
  (conditional auto-create)` immediately AFTER the
  `## Pre-check — Existing file` section's example block and immediately
  BEFORE `## Phase 1 — Research`.
- **Phase 6 step 2.5 insertion:** AFTER the step 2 body (current text
  begins "Write the plan file") and BEFORE the step 3 heading
  (`**Plan index — do not touch.**`).
- **Phase 6 step 2 amendment:** in-place edit to the step 2 paragraph.
- **Phase 6 step 4 extension:** in-place rewrite of the "Present the
  result:" template block.

Re-grep these anchor strings before editing.

#### Parser edit (Arguments section — add `parent=<name>` recognition)

In the existing `**Detection:**` enumeration in `## Arguments`, add a new
bullet (between `rounds N` and the "Everything else …" catchall):

```
- `parent=<name>` (where `<name>` matches `[A-Za-z0-9._-]+`) — delegation
  marker indicating this `/draft-plan` invocation was dispatched by a
  parent skill (`research-and-plan`, `research-and-go`, or `run-plan`).
  The parser records the value into `$DRAFT_PLAN_PARENT` (or notes its
  presence) and **strips** the token from the description segment so it
  does NOT appear in the plan body or research-agent prompts.
```

Stripping is mandatory: (a) a leaked token contaminates research-summary
text, headings, and quoted descriptions; (b) a description legitimately
containing the substring `parent=research-and-plan` (e.g. this plan's own
description) must NOT match the gate. The parser-strip-then-check pattern
eliminates both. The existing parser is described in prose, not bash —
the new bullet plus the strip clause suffice; the Phase 0 gate then reads
the parser-captured `$DRAFT_PLAN_PARENT`, never substring-grepping raw
`$ARGUMENTS`.

#### Parser→bash handoff (closes R-F3)

The existing skill's parser is **prose-only** — the orchestrator-LLM
scans `$ARGUMENTS` and produces `$OUTPUT_FILE`, `$TRACKING_ID`, and now
`$DRAFT_PLAN_PARENT`. Bash fences cannot read these values implicitly:
the orchestrator must EMIT them as the first thing in Phase 0's first
fence. Pin this contract with a prose paragraph IMMEDIATELY before the
first Phase 0 bash fence:

> **Parser→bash handoff (orchestrator-emitted literal).** The first
> bash fence in Phase 0 MUST begin with three assignments based on the
> prose-parser pass over `$ARGUMENTS`:
>
> ```bash
> OUTPUT_FILE="<parser-resolved output path>"
> TRACKING_ID="<derived slug>"
> DRAFT_PLAN_PARENT="<parent token if recognized, else empty>"
> ```
>
> The orchestrator-LLM substitutes the bracketed placeholders with
> literal strings before running the fence. No subsequent fence may
> reference these variables until this handoff has happened.

Phase 3 includes a conformance assertion that this anchor prose
exists in SKILL.md.

#### OUTPUT_FILE_* canonical conventions (UNCONDITIONAL — closes R-F2)

The existing parser produces a single variable `$OUTPUT_FILE` whose value
is the path the orchestrator wrote to the file system. Three cases:

1. **Bare slug** (`THERMAL_PLAN.md`) — parser resolves via
   `$ZSKILLS_PLANS_DIR/THERMAL_PLAN.md`. `$ZSKILLS_PLANS_DIR` is the
   project's plans directory (defaults to `plans/` when config silent,
   typically `docs/plans/` in this repo).
2. **Repo-relative path** (`docs/plans/X.md`) — used as-is.
3. **Absolute path** (`/workspaces/zskills/docs/plans/X.md`) — used as-is.

Phase 0 introduces THREE explicit variables. **All three are derived in
a sourceable helper `derive_output_paths` that is called BOTH initially
(unconditionally, before the gate) AND again after `WT_PATH` is reassigned
on the create branch.** Re-derivation on the create branch is the only
way the variables differ across the SKIP vs. create paths; they are
always defined.

Initial derivation (unconditional, before the gate fires):

```bash
# Compute MAIN_ROOT, TOPLEVEL, IN_WORKTREE once, unconditionally.
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TOPLEVEL=$(git rev-parse --show-toplevel)
if [ "$MAIN_ROOT" = "$TOPLEVEL" ]; then
  IN_WORKTREE=0
else
  IN_WORKTREE=1
fi

# WT_PATH starts at $TOPLEVEL; may be reassigned by the create branch.
WT_PATH="$TOPLEVEL"

# derive_output_paths — sets OUTPUT_FILE_ABS and OUTPUT_FILE_REL from
# the current $WT_PATH + $OUTPUT_FILE.
derive_output_paths() {
  if [[ "$OUTPUT_FILE" = /* ]]; then
    # Absolute path. If we're about to use a freshly-created worktree
    # (AUTO_WORKTREE_CREATED=1):
    #   - Path already inside the worktree → accept.
    #   - Path inside MAIN_ROOT → REMAP to the worktree (common case:
    #     user typed an absolute path because they know the project
    #     layout, not because they wanted to write outside the WT).
    #     Closes DA-R3 F5.
    #   - Path outside both → refuse (genuinely out-of-tree).
    if [ "${AUTO_WORKTREE_CREATED:-0}" = "1" ]; then
      case "$OUTPUT_FILE" in
        "$WT_PATH"/*)
          OUTPUT_FILE_ABS="$OUTPUT_FILE"
          ;;
        "$MAIN_ROOT"/*)
          # Remap MAIN-relative prefix to the worktree.
          OUTPUT_FILE_ABS="$WT_PATH/${OUTPUT_FILE#$MAIN_ROOT/}"
          echo "draft-plan: remapped absolute path '$OUTPUT_FILE' → '$OUTPUT_FILE_ABS' (auto-worktree)" >&2
          ;;
        *)
          echo "draft-plan: refusing absolute path '$OUTPUT_FILE' outside MAIN_ROOT '$MAIN_ROOT' and worktree '$WT_PATH'" >&2
          exit 1
          ;;
      esac
    else
      OUTPUT_FILE_ABS="$OUTPUT_FILE"
    fi
  else
    OUTPUT_FILE_ABS="$WT_PATH/$OUTPUT_FILE"
  fi
  OUTPUT_FILE_REL=$(realpath --relative-to="$WT_PATH" --no-symlinks "$OUTPUT_FILE_ABS" 2>/dev/null \
                    || python3 -c "import os,sys;print(os.path.relpath(sys.argv[1],sys.argv[2]))" \
                         "$OUTPUT_FILE_ABS" "$WT_PATH")
  if [ -z "$OUTPUT_FILE_REL" ]; then
    echo "draft-plan: failed to derive OUTPUT_FILE_REL — neither 'realpath --relative-to' nor 'python3' is available. Install GNU coreutils 8.23+ or python3." >&2
    exit 1
  fi
}
AUTO_WORKTREE_CREATED=0
derive_output_paths   # initial — unconditional
```

(`realpath --relative-to` is available on modern coreutils; the python3
fallback is a safety net. If neither is available the orchestrator should
fail with a clear message. **No jq** anywhere — bash regex + coreutils only.)

After the gate fires, the create branch sets `AUTO_WORKTREE_CREATED=1`,
reassigns `$WT_PATH`, then calls `derive_output_paths` a second time.
The SKIP branch leaves `$WT_PATH=$TOPLEVEL` and does not re-derive.
Either way, `WT_PATH`, `OUTPUT_FILE_ABS`, `OUTPUT_FILE_REL` are all set
when Phase 0 ends. **These are then persisted to a state file (next
section) so Phase 6 step 2 and step 2.5 can read them.**

#### State-file persistence across fences (NEW — closes R-F1 / R-F5 / R-F6)

Bash fences are one-shot subprocesses; named variables do not survive
across fences. The previous plan version claimed "Phase 0 exports …
named variables" — that prose contradicted the verbatim bash, which
used no `export`. The fix: **Phase 0's final bash fence writes a state
file under `/tmp/`; every Phase 1+ fence that needs Phase 0's outputs
sources that file at its top.** No `cd`, no cwd reliance.

State-file path: `/tmp/zskills-draftplan-state-${TRACKING_ID}.env`.
Written at the END of Phase 0 (BOTH branches — SKIP and create) and
consumed at the START of every Phase 1+ fence that references any of
`$WT_PATH`, `$OUTPUT_FILE_ABS`, `$OUTPUT_FILE_REL`, `$IN_WORKTREE`,
`$AUTO_WORKTREE_CREATED`, `$TRACKING_ID`, `$DRAFT_PLAN_PARENT`,
`$BRANCH_PREFIX`, or `$PIPELINE_ID`.

Write template (end of Phase 0):

```bash
STATE_FILE="/tmp/zskills-draftplan-state-${TRACKING_ID}.env"
{
  echo "WT_PATH=$(printf %q "$WT_PATH")"
  echo "OUTPUT_FILE=$(printf %q "$OUTPUT_FILE")"
  echo "OUTPUT_FILE_ABS=$(printf %q "$OUTPUT_FILE_ABS")"
  echo "OUTPUT_FILE_REL=$(printf %q "$OUTPUT_FILE_REL")"
  echo "TRACKING_ID=$(printf %q "$TRACKING_ID")"
  echo "DRAFT_PLAN_PARENT=$(printf %q "${DRAFT_PLAN_PARENT:-}")"
  echo "PIPELINE_ID=$(printf %q "${PIPELINE_ID:-}")"
  echo "AUTO_WORKTREE_CREATED=${AUTO_WORKTREE_CREATED:-0}"
  echo "IN_WORKTREE=${IN_WORKTREE:-0}"
  echo "BRANCH_PREFIX=$(printf %q "${BRANCH_PREFIX:-feat/}")"
} > "$STATE_FILE"
```

Consume template (top of every Phase 1+ fence that needs these):

```bash
TRACKING_ID="<orchestrator-emitted slug, same as Phase 0>"
STATE_FILE="/tmp/zskills-draftplan-state-${TRACKING_ID}.env"
[ -f "$STATE_FILE" ] && . "$STATE_FILE" || {
  echo "draft-plan: Phase 0 state file missing at $STATE_FILE" >&2
  exit 1
}
```

The consumer needs `$TRACKING_ID` to construct the path. The
orchestrator-LLM re-emits `TRACKING_ID=<value>` literally at the top of
each consumer fence (symmetric with the parser→bash handoff). Phase 3
asserts both write and consume patterns appear in SKILL.md.

**State-file lifecycle (NEW — closes R3-Reviewer F1):** the state file is
written ONCE at the end of Phase 0, sourced by Phase 6 step 2 + step
2.5, then DELETED at the end of Phase 6 step 4 (after the report is
emitted). Path is keyed on `${TRACKING_ID}` alone so cleanup is
deterministic per-slug. Phase 0 truncation-writes (`>` redirect) ensure
that any stale file from a prior aborted run is overwritten cleanly on
re-invocation; the Phase 6 step 4 cleanup is belt-and-suspenders against
`/tmp/` accumulation on persistent-tmp distros.

**Concurrent-slug race (D&C note — closes R3-Reviewer F2 / DA F4):**
two simultaneous `/draft-plan` invocations with the SAME slug (same
`TRACKING_ID`) share `/tmp/zskills-draftplan-state-${TRACKING_ID}.env`.
This is by design: `create-worktree.sh`'s `--allow-resume` flag and its
TOCTOU remap handle the worktree-creation race at the script layer, and
the state file converges to whichever Phase-0 process writes last (the
file's contents are deterministic for a given slug, so the practical
damage is bounded — Phase 6 step 2.5's staged-set defense catches any
divergence). Concurrent SAME-slug runs are NOT a supported workflow:
the user should serialize them (or use distinct slugs for parallel
drafting). Parallel pipelines with DIFFERENT slugs are fully supported
— per-slug state-file keying prevents cross-pipeline collision.

#### Phase 0 — auto-worktree gate (SKIP conditions, evaluated in this order)

The gate SKIPS auto-worktree creation when **ANY** of:

1. `execution.landing != "pr"` in `.claude/zskills-config.json`
2. `execution.main_protected != true` in `.claude/zskills-config.json`
3. Caller is delegated: `$ZSKILLS_PIPELINE_ID` is non-empty **OR** the
   pre-stripped `$ARGUMENTS` head contained a recognized
   `parent=<name>` token (`research-and-plan`, `research-and-go`, or
   `run-plan`). The parser captures this into `$DRAFT_PLAN_PARENT`
   during the Arguments pass; the gate checks `$DRAFT_PLAN_PARENT`
   against a **known-name allowlist** (`research-and-plan` |
   `research-and-go` | `run-plan`) — unrecognized parent names do NOT
   count as delegation (they fall through to would-create). See the
   `case` statement in the "Verbatim bash" block below; canary case 7
   asserts the unrecognized-parent behavior.
4. Orchestrator is already in a worktree: `IN_WORKTREE=1`.
5. **`$TOPLEVEL/.zskills-tracked` exists** — positive "I'm already in a
   managed worktree owned by some pipeline" signal (NEW — closes D-B).
   `create-worktree.sh` writes this file unconditionally into every
   worktree it creates. This SKIP catches /run-plan, /do, /fix-issues,
   and any other zskills caller that already created a worktree,
   without each parent skill having to remember to emit `parent=<name>`.

If none of the above trigger, fall through to worktree creation.

#### Phase 0 — verbatim bash (copy into the skill body)

Config read (landing + main_protected + branch_prefix) — bash regex, NO jq.
**Closes D-C** (branch_prefix was hardcoded `feat/` in v2):

```bash
CONFIG_FILE="$MAIN_ROOT/.claude/zskills-config.json"
LANDING_HINT=""
MAIN_PROTECTED="false"
BRANCH_PREFIX="feat/"   # default if config silent
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_CONTENT=$(cat "$CONFIG_FILE")
  if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    LANDING_HINT="${BASH_REMATCH[1]}"
  fi
  if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
    MAIN_PROTECTED="${BASH_REMATCH[1]}"
  fi
  if [[ "$CONFIG_CONTENT" =~ \"branch_prefix\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    BRANCH_PREFIX="${BASH_REMATCH[1]}"
  fi
fi
```

Delegation detection (the parser has already populated `$DRAFT_PLAN_PARENT`
from the stripped `parent=<name>` token, if any):

```bash
DELEGATED=0
if [ -n "${ZSKILLS_PIPELINE_ID:-}" ]; then
  DELEGATED=1
elif [ -n "${DRAFT_PLAN_PARENT:-}" ]; then
  # Word-boundary safe — value comes from the parser, never a raw
  # substring grep of $ARGUMENTS. Recognized parent names:
  case "$DRAFT_PLAN_PARENT" in
    research-and-plan|research-and-go|run-plan) DELEGATED=1 ;;
  esac
fi
```

`.zskills-tracked` SKIP detection (NEW — closes D-B; trust-model guard
NEW — closes DA-R3 F3):

```bash
ALREADY_MANAGED=0
# Trust model: .zskills-tracked is a "managed worktree" signal. We only
# trust it when TOPLEVEL is NOT MAIN_ROOT — i.e., the file is in an
# actual worktree, not stale debris committed/copied into MAIN. Without
# this guard, a stray `.zskills-tracked` in MAIN would silently disable
# auto-worktree creation forever — the exact friction issue #226 set
# out to eliminate.
if [ -f "$TOPLEVEL/.zskills-tracked" ] && [ "$TOPLEVEL" != "$MAIN_ROOT" ]; then
  ALREADY_MANAGED=1
fi
```

TRACKING_ID derivation (matches the existing idiom in the skill's
Phase-1 tracking block). NOTE: `$TRACKING_ID` was already emitted by
the parser→bash handoff fence; this validates it:

```bash
# Re-derivation only as a safety net if the orchestrator didn't emit
# TRACKING_ID in the handoff fence (it should have).
if [ -z "${TRACKING_ID:-}" ]; then
  TRACKING_ID=$(basename "$OUTPUT_FILE" .md | tr '[:upper:]_' '[:lower:]-')
fi
# Validate against create-worktree's slug regex BEFORE invocation so we
# emit a friendly message instead of letting create-worktree.sh exit 5.
if [[ ! "$TRACKING_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "draft-plan: derived slug '$TRACKING_ID' is invalid (need [A-Za-z0-9._-]+). Rename your plan file." >&2
  exit 5
fi
```

Combined gate + invocation (the canonical block — copy verbatim):

```bash
if [ "$LANDING_HINT" != "pr" ] \
   || [ "$MAIN_PROTECTED" != "true" ] \
   || [ "$DELEGATED" = "1" ] \
   || [ "$IN_WORKTREE" = "1" ] \
   || [ "$ALREADY_MANAGED" = "1" ]; then
  echo "draft-plan: auto-worktree SKIPPED (landing=$LANDING_HINT main_protected=$MAIN_PROTECTED delegated=$DELEGATED in_worktree=$IN_WORKTREE already_managed=$ALREADY_MANAGED)" >&2
  AUTO_WORKTREE_CREATED=0
else
  WT_PATH=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
    --prefix draftplan \
    --branch-name "${BRANCH_PREFIX}${TRACKING_ID}" \
    --purpose "draft-plan auto-worktree; plan=${TRACKING_ID}" \
    --pipeline-id "draft-plan.${TRACKING_ID}" \
    --allow-resume \
    "${TRACKING_ID}")
  RC=$?
  if [ "$RC" -eq 2 ]; then
    echo "draft-plan: worktree already exists for ${TRACKING_ID}; resuming at $WT_PATH" >&2
  elif [ "$RC" -ne 0 ]; then
    echo "create-worktree failed (rc=$RC) for /draft-plan auto-worktree" >&2
    exit "$RC"
  fi
  AUTO_WORKTREE_CREATED=1
  # Re-derive OUTPUT_FILE_ABS / OUTPUT_FILE_REL now that WT_PATH points
  # to the worktree.
  derive_output_paths
fi
```

**Caller-contract constraint:** `--pipeline-id` MUST appear within 12 lines
of the opening `bash ".../create-worktree.sh" \` (line 1 of the block here,
with `--pipeline-id` on line 5 — passes the conformance check in the
`create-worktree.sh caller contract` block of `tests/test-skill-conformance.sh`).

**`exit RC` does NOT halt the orchestrator on its own.** Bash fences are
one-shot subprocesses; an `exit` inside the fence terminates only that
subprocess. The skill prose MUST instruct the orchestrator, in prose
immediately following the bash fence, to read `$?` and HALT THE SKILL
when non-zero. The exact prose to insert (verbatim, after the fence):

> If this fence's exit code is non-zero, STOP `/draft-plan` immediately —
> do not proceed to Phase 1. Re-surface the fence's stderr to the user
> and exit the skill. The fence's `exit "$RC"` terminates the bash
> subprocess only; the orchestrator must observe the non-zero exit and
> halt voluntarily.

**Exit-code routing (per-code policy):**

| RC | Meaning | Action |
|---|---|---|
| 0 | Created | Proceed; `AUTO_WORKTREE_CREATED=1` |
| 2 | Path exists / TOCTOU | Treat as resume; emit note, proceed |
| 3 | Poisoned branch (behind base) | Surface stderr + recovery prose, exit 3 |
| 4 | Branch ahead w/o `--allow-resume` | (will not occur — flag is set) |
| 5 | Input validation | Surface stderr, exit 5 |
| 6 | Network fetch failure | Surface stderr, exit 6 (retryable) |
| 7 | ff-merge impossible | Surface stderr, exit 7 |
| 8 | Post-create write failed (rolled back) | Surface stderr, exit 8 |
| 9 | Consumer stub failed | Surface stderr, exit 9 |
| 10 | Local main ahead of origin (PR #225) | Surface stderr + recovery prose, exit 10 |

`/draft-plan` never auto-retries. Every non-zero RC except 2 aborts with
the script's stderr surfaced verbatim AND the orchestrator's halt.

**User-facing recovery prose (NEW — closes D-D).** For rc=3 and rc=10
specifically, the orchestrator MUST emit a follow-up paragraph to the
user (in addition to surfacing `create-worktree.sh`'s stderr verbatim):

- **rc=3 (poisoned branch):**

  > The branch `${BRANCH_PREFIX}${TRACKING_ID}` is stale and strictly
  > behind `main`. To recover: either rebase the branch onto current
  > main (if it has prior work worth keeping), OR delete it and re-run
  > `/draft-plan`:
  > ```
  > git branch -D ${BRANCH_PREFIX}${TRACKING_ID}
  > git push origin --delete ${BRANCH_PREFIX}${TRACKING_ID}  # if pushed
  > /draft-plan <your original args>
  > ```
  > `/draft-plan` does NOT auto-delete branches — that's the user's
  > call (per CLAUDE.md "Worktree Rules").

- **rc=10 (local main ahead of origin):** surface the
  `create-worktree.sh` stderr verbatim — that script's message already
  spells out the recovery (`git fetch origin && git reset --hard
  origin/main` or push the local commits). The orchestrator adds:
  > `/draft-plan`'s auto-worktree creation is blocked until your local
  > `main` matches `origin/main`. Reconcile manually, then re-run.

#### Post-creation re-Pre-check (resume case + first-run modernization)

The existing top-of-skill Pre-check reads from MAIN's cwd. Two cases the
re-Pre-check handles:

1. **Resume case (rc=2):** the in-progress plan file lives at
   `$OUTPUT_FILE_ABS` (= `$WT_PATH/$OUTPUT_FILE_REL`), not in MAIN. The
   original Pre-check misses it.

2. **Modernization-from-MAIN case (rc=0, NEW — closes D-H):** the user
   invoked `/draft-plan` on a slug whose plan file exists in MAIN but
   not yet in the fresh worktree. The original Pre-check saw the MAIN
   file and told research agents "modernize", but Phase 6 step 2 would
   write to `$OUTPUT_FILE_ABS` in the new worktree — losing the prior
   content. The fix: on rc=0, `cp` MAIN's prior plan file into the
   worktree BEFORE Phase 1 starts, so the modernization input is
   preserved.

Phase 0 adds the re-Pre-check after the worktree-resolution fence:

```bash
# On rc=0 (fresh worktree), seed the prior plan file from MAIN if it
# existed there. This preserves the modernization-input contract that
# the top-of-skill Pre-check established.
if [ "$AUTO_WORKTREE_CREATED" = "1" ]; then
  MAIN_PRIOR="$MAIN_ROOT/$OUTPUT_FILE"
  if [ -f "$MAIN_PRIOR" ] && [ ! -f "$OUTPUT_FILE_ABS" ]; then
    mkdir -p "$(dirname "$OUTPUT_FILE_ABS")"
    cp "$MAIN_PRIOR" "$OUTPUT_FILE_ABS"
    echo "draft-plan: seeded prior plan from $MAIN_PRIOR → $OUTPUT_FILE_ABS (modernization input)" >&2
  fi
fi

# Re-announce existing plan file at $OUTPUT_FILE_ABS for research agents.
if [ -f "$OUTPUT_FILE_ABS" ]; then
  echo "draft-plan: existing plan file found at $OUTPUT_FILE_ABS — treating as modernization input" >&2
fi
```

Skill prose immediately after the bash: "This block is the canonical
Pre-check for the worktree-aware case; the top-of-skill Pre-check (which
runs against MAIN before Phase 0) still applies on the SKIP path. On the
create path, this block (a) seeds MAIN's prior plan file into the fresh
worktree so the modernization input is preserved, and (b) re-announces
the file's presence to research agents. The two Pre-checks COMPLEMENT
each other; neither supersedes the other." (Closes R-F9.)

**No `cd` in Phase 0 itself.** Bash fences are one-shot — CWD does not
persist across them. Phase 0 persists `WT_PATH`, `AUTO_WORKTREE_CREATED`,
`IN_WORKTREE`, `OUTPUT_FILE_ABS`, `OUTPUT_FILE_REL`, `DRAFT_PLAN_PARENT`
(if any), `TRACKING_ID`, `BRANCH_PREFIX` via the **state file** described
above; downstream fences source the state file at their top. Subshell
`$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` for path resolution
is fine — it does not mutate the orchestrator's cwd. Subshell `( cd
"$WT_PATH" && ... )` for individual commands that depend on cwd (the
skill-version-bump dance, the `git commit` that triggers
`block-stale-skill-version.sh`) is also fine and is explicitly required
for those cases — see "Hook composition" below.

#### Hook composition with `git -C` from foreign cwd (NEW — closes D-A / R-F12 / D-J)

> **RESOLVED (issues #391 + #393).** The worktree-blindness described in
> this section was closed by the PR that landed those two issues:
>
>   - `hooks/block-stale-skill-version.sh` now switches its matcher to
>     `is_git_subcommand_in_chain` so `cd /tmp/wt && git commit` matches,
>     inlines `extract_cd_target`, resolves an `EFFECTIVE_REPO_ROOT`, and
>     invokes `scripts/skill-version-stage-check.sh` in a subshell `cd`'d
>     to that root.
>   - `scripts/skill-version-stage-check.sh` resolves `REPO_ROOT` via
>     `git rev-parse --show-toplevel` (CWD-rooted), falling back to
>     `$CLAUDE_PROJECT_DIR` then `$PWD` for backward compat.
>   - `hooks/block-unsafe-project.sh.template` applies the same
>     cd-target-precedence pattern to all three LOCAL_ROOT sites
>     (commit / cherry-pick / push) so tracking-marker enforcement fires
>     on worktree commits.
>   - Worktree-fixture cases in `tests/test-skill-version-enforcement.sh`
>     and `tests/test-tracking-integration.sh` lock the fix.
>
> The historical analysis below is preserved for context.

`block-stale-skill-version.sh` (PreToolUse hook on every `git commit`)
delegates to `scripts/skill-version-stage-check.sh`, which reads
`REPO_ROOT="${CLAUDE_PROJECT_DIR:?...}"` and runs
`git -C "$REPO_ROOT" diff --cached --name-only`. `$CLAUDE_PROJECT_DIR`
is **MAIN's root**, not the worktree's. If the orchestrator runs
`git -C "$WT_PATH" commit` from MAIN's cwd, the hook inspects MAIN's
index — which has nothing staged from the WT commit. Failure modes:
(1) **false-negative clear** — un-bumped commit allowed because MAIN's
index is empty; (2) **false-positive deny** — MAIN's index has unrelated
staged files from another context, causing the hook to deny a clean
WT commit.

The structurally correct fix is a hook-side change (resolve `REPO_ROOT`
via `git rev-parse --show-toplevel` of the invoking shell). **Out of
scope for this plan — file as follow-up issue.** Even subshell-`cd` into
the worktree doesn't fully help: the hook re-resolves `$CLAUDE_PROJECT_DIR`
to MAIN, and also `bash "$HASH" "$REPO_ROOT/$sk"` reads from MAIN's
filesystem (where the bump wasn't applied).

**Bottom line: the hook is effectively a no-op for WT commits today.**
This plan does NOT rely on it as a backstop. Enforcement for this
plan's commits comes from:

1. **Implementing-agent discipline** — the bump dance is an explicit
   work item; the agent runs it before staging.
2. **Phase 3 conformance assertion** `metadata.version format` — fails
   if any of the three edited SKILL.mds has a non-today date prefix.
3. **CI** — `tests/test-skill-conformance.sh` is the push-time backstop.

The subshell-`cd` in Phase 1's bump dance (and the implementation
commit) is still used — it ensures the dance's relative `scripts/...`
and `skills/...` paths resolve to the worktree's copies (where edits
live), even though it doesn't fix the hook itself.

#### Phase 6 — step 2 amendment

Replace the existing step 2 body:

> 2. **Write the plan file** to the output path. The user can't review
>    what they can't read — plans are often too large to meaningfully
>    summarize in chat. Write first, then let the user read the actual
>    file.

with (the orchestrator-emitted `TRACKING_ID=` and state-file source must
precede the actual file write):

> 2. **Write the plan file** to `$OUTPUT_FILE_ABS`. The orchestrator
>    first sources the Phase 0 state file:
>    ```bash
>    TRACKING_ID="<orchestrator-emitted slug, same as Phase 0>"
>    STATE_FILE="/tmp/zskills-draftplan-state-${TRACKING_ID}.env"
>    [ -f "$STATE_FILE" ] && . "$STATE_FILE" || { echo "draft-plan: Phase 0 state file missing"; exit 1; }
>    ```
>    then writes the plan content to `$OUTPUT_FILE_ABS` (the worktree-aware
>    absolute path computed in Phase 0; when Phase 0 SKIPPED, it resolves
>    to the main-tree path). The user can't review what they can't
>    read — plans are often too large to meaningfully summarize in chat.
>    Write first, then let the user read the actual file.

#### Phase 6 — step 2.5 auto-commit (verbatim bash — consumes state file, closes R-F1)

Insert as a new bolded sub-step between the (amended) Phase 6 step 2 body
and step 3's `**Plan index — do not touch.**` heading. Gate: read
`$IN_WORKTREE` from the Phase 0 state file (NOT cwd-derived
`git rev-parse --show-toplevel`).

```bash
TRACKING_ID="<orchestrator-emitted slug, same as Phase 0>"
STATE_FILE="/tmp/zskills-draftplan-state-${TRACKING_ID}.env"
[ -f "$STATE_FILE" ] && . "$STATE_FILE" || {
  echo "draft-plan: Phase 0 state file missing at $STATE_FILE — Phase 0 did not run" >&2
  exit 1
}

# Gate: are we in any worktree (auto-created OR pre-existing)?
# IN_WORKTREE comes from Phase 0; AUTO_WORKTREE_CREATED=1 implies the
# orchestrator is logically operating in $WT_PATH even if its cwd is
# still MAIN. Either signal triggers the auto-commit.
if [ "$IN_WORKTREE" != "1" ] && [ "$AUTO_WORKTREE_CREATED" != "1" ]; then
  echo "draft-plan: not in a worktree; skipping auto-commit" >&2
  COMMIT_SHA=""
else
  # Resolve co-author via the canonical /commit helper.
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  # $COMMIT_CO_AUTHOR is now set (possibly empty — that is a valid
  # consumer opt-out; matches commit/SKILL.md:347).

  # No-op guard: if the plan file is unchanged from HEAD, skip the commit.
  if git -C "$WT_PATH" diff --quiet HEAD -- "$OUTPUT_FILE_REL" 2>/dev/null \
     && [ -z "$(git -C "$WT_PATH" status --porcelain -- "$OUTPUT_FILE_REL")" ]; then
    echo "draft-plan: plan file unchanged from HEAD; skipping auto-commit" >&2
    COMMIT_SHA=""
  else
    git -C "$WT_PATH" add "$OUTPUT_FILE_REL"
    STAGED=$(git -C "$WT_PATH" diff --cached --name-only)
    if [ -z "$STAGED" ]; then
      echo "draft-plan: no staged changes after add (already in HEAD); skipping auto-commit" >&2
      COMMIT_SHA=""
    elif [ "$STAGED" != "$OUTPUT_FILE_REL" ]; then
      echo "draft-plan: unexpected staged set: $STAGED (expected $OUTPUT_FILE_REL only)" >&2
      echo "draft-plan: worktree may have dirty state from a prior session — manually \`git -C $WT_PATH status\` to inspect" >&2
      exit 1
    else
      SLUG_SHORT=$(basename "$OUTPUT_FILE_REL" .md)
      # Derive a one-line summary: first try the plan's frontmatter
      # `title:` field; fall back to the first non-empty line of the
      # Overview section; fall back to the slug.
      ONELINER=$(awk '/^title:[[:space:]]*/{sub(/^title:[[:space:]]*/,"");print;exit}' "$OUTPUT_FILE_ABS" 2>/dev/null)
      if [ -z "$ONELINER" ]; then
        ONELINER=$(awk '/^## Overview/{flag=1;next} flag && NF{print;exit}' "$OUTPUT_FILE_ABS" 2>/dev/null)
      fi
      [ -z "$ONELINER" ] && ONELINER="$SLUG_SHORT"
      # Truncate to keep subject ≤ ~72 chars total.
      ONELINER=$(printf '%s' "$ONELINER" | cut -c1-60)

      if [ -n "$COMMIT_CO_AUTHOR" ]; then
        git -C "$WT_PATH" commit \
          --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" \
          -m "$(cat <<EOF
docs(plans): draft ${SLUG_SHORT} — ${ONELINER}
EOF
)"
      else
        git -C "$WT_PATH" commit \
          -m "$(cat <<EOF
docs(plans): draft ${SLUG_SHORT} — ${ONELINER}
EOF
)"
      fi
      COMMIT_SHA=$(git -C "$WT_PATH" rev-parse HEAD)
    fi
  fi
fi
```

**Note on heredoc quoting.** The heredoc is unquoted `<<EOF` here because
`${SLUG_SHORT}` and `${ONELINER}` must be expanded; `commit/SKILL.md:350`
uses `<<'EOF'` because its body is fully literal. Both forms are canonical.
`$SLUG_SHORT` and `$ONELINER` are derived locally (not user-typed) and
`cut -c1-60` bounds the input — no command-injection surface. The
`--trailer` form for `Co-Authored-By:` is verified canonical at
`skills/commit/SKILL.md:347-353`.

**Commit-message rules:**
- Subject form: `docs(plans): draft <SLUG_SHORT> — <one-liner>` (em-dash,
  not hyphen). Verified against `git log -- docs/plans/`.
- `<SLUG_SHORT>` is `basename "$OUTPUT_FILE_REL" .md`
  (e.g. `DRAFT_PLAN_AUTO_WORKTREE`).
- `<one-liner>` is derived as shown above; never left as a literal
  placeholder string in the actual commit.
- Co-Authored-By trailer goes via `--trailer`, matching the canonical
  form at `skills/commit/SKILL.md:347-353`.

**No-op behavior (AC5).** The block distinguishes three cases:
(a) plan file unchanged from HEAD → skip commit, `COMMIT_SHA=""`,
exit 0; (b) `git add` stages nothing → skip commit, exit 0; (c) unexpected
non-plan paths staged → `exit 1` with a recovery message pointing the
user at `git status` in the worktree (NEW — closes D-G's case 2).

**Hook-gating note (verified).** `scripts/skill-version-stage-check.sh:46`
filters staged paths via `^(skills|block-diagram)/([^/]+)/` —
`docs/plans/*.md` does NOT match, so `block-stale-skill-version.sh` is a
no-op on this commit. **No version-bump dance required** for the
plan-doc-only commit. (If a future user has unrelated SKILL.md edits in
the worktree, the staged-set defense above refuses to commit, preserving
the agent's hands-off discipline.)

#### Phase 6 step 4 — extended "Present the result" template

Replace the existing Phase 6 step 4 prose with an extended template that
conditionally surfaces worktree/branch/commit when applicable:

```
Final report to the user:
  - Plan path: <OUTPUT_FILE_REL>
  - Phases: <N>
  - Adversarial-review rounds: <R>
  - Quality score: <Q>/10
  [if COMMIT_SHA != "" AND AUTO_WORKTREE_CREATED = "1"]
  - Worktree (auto-created): <WT_PATH>
  - Branch:   <BRANCH_PREFIX><TRACKING_ID>
  - Commit:   <COMMIT_SHA> docs(plans): draft <SLUG_SHORT> — <one-liner>
  - Cleanup:  when done, `git worktree remove "<WT_PATH>" && git branch -D <BRANCH_PREFIX><TRACKING_ID>` (your call)
  - Next:     run `/commit pr auto` (or land via your usual workflow)
  [else if COMMIT_SHA != "" AND IN_WORKTREE = "1"]
  - Worktree (pre-existing): <WT_PATH>
  - Branch:   <whichever branch is on HEAD>
  - Commit:   <COMMIT_SHA> docs(plans): draft <SLUG_SHORT> — <one-liner>
  - Cleanup:  manage per your usual worktree workflow
  - Next:     continue your usual landing workflow
  [else]
  - Plan is uncommitted in the current working tree.
  - Next: stage/commit per your project's landing workflow.
```

The two-branch worktree differentiation lets the user know whether
`/draft-plan` created the worktree this invocation (so they may want to
clean it up after landing) vs. operated inside an existing worktree
that's theirs to manage.

No `git push`, no `gh pr create`, no `/commit` dispatch — landing is the
user's choice (issue #226: "Auto-pushing the branch or auto-creating a PR"
is out-of-scope). The "Next" line is advisory text only.

**State-file cleanup (NEW — closes R3-Reviewer F1).** After the report
is presented to the user, delete the Phase 0 state file. Append to step
4's bash:

```bash
TRACKING_ID="<orchestrator-emitted slug, same as Phase 0>"
STATE_FILE="/tmp/zskills-draftplan-state-${TRACKING_ID}.env"
rm -f "$STATE_FILE"   # deterministic per-slug cleanup; idempotent
```

The `rm -f` is intentionally not error-fatal: if Phase 0 SKIPPED (no
state file written) or a prior cleanup already ran, the `-f` flag keeps
this idempotent. Cleanup runs UNCONDITIONALLY (both SKIP and create
paths) — Phase 0 always writes the state file, so cleanup always has
something to remove.

#### Multi-commit version-bump discipline

Per CLAUDE.md "Skill versioning", every commit that touches
`skills/<name>/` MUST bump that skill's `metadata.version`. This plan
creates several commits:

| Phase | Files touched (skills/) | Bump required for |
|-------|------------------------|-------------------|
| 1 | `skills/draft-plan/` | `skills/draft-plan/SKILL.md` |
| 2 | `skills/research-and-plan/`, `skills/run-plan/` | both SKILL.md files |
| 3 | `tests/` only | (none — tests/ is not a skill) |
| 4 | `tests/` only | (none) |
| 5 | (verification only — no SKILL.md edits expected) | none if no edits |

**If Phase 3, 4, or 5 surfaces a spec gap that requires a one-line fix
to `skills/draft-plan/SKILL.md` or `skills/research-and-plan/SKILL.md`
or `skills/run-plan/SKILL.md`, that follow-up commit MUST repeat the
version-bump dance for the touched skill** before committing. The
**enforcement mechanism for THIS plan is the implementing agent's
discipline + Phase 3 conformance assertion + CI** — NOT the
`block-stale-skill-version.sh` PreToolUse hook, which is a no-op for
`git -C "$WT_PATH" commit` from foreign cwd (see "Hook composition"
above). Do NOT `--no-verify` / `--amend`. If a hook deny envelope DOES
fire (e.g., the orchestrator is operating from a non-foreign cwd), its
`permissionDecisionReason` carries the exact bump command — run it
inline and re-issue the commit.

#### Hard constraints

- **NO bare top-level `cd` that mutates the orchestrator shell's cwd.**
  Subshell `$(cd … && pwd)` for path resolution is the established
  idiom and is fine. Subshell `( cd "$WT_PATH" && ... )` for individual
  commands that depend on cwd (skill-version-bump dance, commits that
  touch `skills/`) is ALSO fine and is required for correct hook
  composition. Use `git -C "$WT_PATH" ...` in every other bash block.
  Bash fences are one-shot.
- **State-file persistence is mandatory.** Phase 0 MUST write
  `/tmp/zskills-draftplan-state-${TRACKING_ID}.env`; downstream fences
  MUST source it.
- **NO `export ZSKILLS_PIPELINE_ID`** anywhere in the skill body (banned
  by `tests/test-skill-conformance.sh:1047-1052`). Pass `--pipeline-id`
  as a flag to `create-worktree.sh` only.
- **NO jq.** Bash regex with `BASH_REMATCH` + coreutils only (project
  rule: `feedback_no_jq_in_skills.md`).
- **NO `git push`** in any block (issue #226 out-of-scope; CLAUDE.md
  L130). Phase 3's conformance assertion guards this with a
  command-position-only regex (see Phase 3).
- **NO `|| true`** on the `create-worktree.sh` invocation or the
  `git commit` (project rule: `feedback_or_true_pattern.md`). Errors
  must propagate.
- **NO `.landed` marker write** in Phase 0 or Phase 6 — `.landed` is
  owned by `/commit land`, not `/draft-plan`.
- **`metadata.version` MUST bump** to today+content-hash (CLAUDE.md
  L187-189); unbumped commits will be caught by Phase 3's conformance
  assertion and by CI.
- **Mirror MUST be regenerated.** `.claude/skills/draft-plan/SKILL.md`
  must be byte-identical to `skills/draft-plan/SKILL.md` after the edit
  (verified via `diff -rq`).
- **Branch name uses `$BRANCH_PREFIX` from config**, defaulting to
  `feat/` when config silent (closes D-C).

### Acceptance Criteria

- [ ] New `## Phase 0 — Worktree setup` heading positioned between the
      `## Pre-check — Existing file` block and `## Phase 1 — Research`.
      Verified by `grep -n '^## Phase 0\|^## Phase 1' skills/draft-plan/SKILL.md`.
- [ ] `## Arguments` section mentions `parent=<name>` recognition AND
      includes the word "strip"/"stripped".
- [ ] Phase 0 body contains literally each of: `LANDING_HINT`,
      `MAIN_PROTECTED`, `BRANCH_PREFIX`, `DELEGATED`, `IN_WORKTREE`,
      `ALREADY_MANAGED`, `DRAFT_PLAN_PARENT`,
      `--pipeline-id "draft-plan.${TRACKING_ID}"`, `--allow-resume`,
      `--prefix draftplan`,
      `--branch-name "${BRANCH_PREFIX}${TRACKING_ID}"`,
      `OUTPUT_FILE_ABS`, `OUTPUT_FILE_REL`,
      `STATE_FILE="/tmp/zskills-draftplan-state-`.
- [ ] Phase 0 body contains the STOP-on-failure prose
      (search: `STOP `/draft-plan` immediately`) AND a post-creation
      re-Pre-check fence reading `$OUTPUT_FILE_ABS` AND a
      modernization-seed block that `cp`s MAIN's prior plan file into the
      worktree on `AUTO_WORKTREE_CREATED=1`.
- [ ] Phase 0 body contains the **parser→bash handoff** prose block
      (search anchor: `Parser→bash handoff (orchestrator-emitted literal)`).
- [ ] `grep -n '^## Phase 0' skills/draft-plan/SKILL.md` returns exactly one line.
- [ ] `diff -rq skills/draft-plan .claude/skills/draft-plan` is silent.
- [ ] Phase 6 contains a step 2.5 bolded sub-heading with the verbatim
      auto-commit block: no-op guard (`git diff --quiet HEAD`),
      staged-set defense, and `--trailer "Co-Authored-By:` (matched via
      ERE with `${VAR}` / `$VAR` tolerance — see Phase 3).
- [ ] Phase 6 step 2.5 sources the state file at the top
      (`[ -f "$STATE_FILE" ] && . "$STATE_FILE"`).
- [ ] Phase 6 step 2 body references `$OUTPUT_FILE_ABS`; step 4 prose
      mentions `Worktree:`, `Branch:`, `Commit:`, AND conditionally
      differentiates `Worktree (auto-created):` vs
      `Worktree (pre-existing):` based on `AUTO_WORKTREE_CREATED` /
      `IN_WORKTREE`.
- [ ] Phase 6 step 4 contains a state-file cleanup fence
      (`rm -f "$STATE_FILE"`) after the report block.
- [ ] No `git push` (command position), no `gh pr create`, no `export
      ZSKILLS_PIPELINE_ID`, no ` jq ` binary call, no `|| true` after
      `create-worktree.sh` or `git commit`. Verified by Phase 3
      conformance assertions (anchored regex avoids prose false-positives).
- [ ] `metadata.version` field has today's `America/New_York` date prefix.
      Phase 3 grep-matches `^  version: "[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[a-f0-9]{6}"`.
- [ ] `argument-hint` frontmatter includes `[parent=<name>]`.

### Dependencies

None — this is the leaf implementation phase. Independent of Phase 2
(parent edits) because Phase 1's SKIP-condition logic detects delegation
via the parser-captured `$DRAFT_PLAN_PARENT` (plus the env var and the
`.zskills-tracked` file as belt-and-suspenders for callers that don't
emit the token).

---

## Phase 2 — Parent-skill delegation signal (/research-and-plan + /run-plan)

### Goal

Edit TWO skills so each emits `parent=<name>` when dispatching `/draft-plan`:

1. `skills/research-and-plan/SKILL.md` — emit `parent=research-and-plan`.
2. `skills/run-plan/SKILL.md` — emit `parent=run-plan` on the auto-mode
   plan-refresh dispatch (closes D-B). Without this, `/run-plan auto`'s
   `/draft-plan` refresh would trip the auto-worktree gate and create a
   second worktree alongside /run-plan's existing PR worktree —
   silently breaking the refresh chain.

(`/research-and-go` does NOT directly dispatch `/draft-plan` — verified
by grep — so no edit needed there. But the `.zskills-tracked` SKIP
condition added in Phase 1 is the safety net: if any future caller
forgets the token, the SKIP catches them too.)

### Work Items

- [ ] **research-and-plan edit.** Locate the `/draft-plan` dispatch
      template at `skills/research-and-plan/SKILL.md` around the
      `### Step 2 — Draft sub-plans` block (search anchor: `Dispatch:`
      followed by `/draft-plan output <path>`). Append the literal token
      `parent=research-and-plan` to the invocation string, positioned
      **immediately after `output <path>` and before the user
      `<description>`** (matching the actual current template — see
      "Exact dispatch template edit" below).
- [ ] **run-plan edit (NEW — closes D-B).** Locate the auto-mode
      `/draft-plan` refresh dispatch at `skills/run-plan/SKILL.md`
      around the `**Check for staleness**` block (search anchor:
      `With \`auto\`: dispatch \`/draft-plan\``). Edit the dispatch prose
      so the actual command-line includes `parent=run-plan` after the
      plan-file path. The current prose says simply "dispatch
      `/draft-plan` on the plan file"; rewrite to: "dispatch `/draft-plan
      <plan-file> parent=run-plan` on the plan file". Bump
      `skills/run-plan/SKILL.md`'s `metadata.version`.
- [ ] Verify `/research-and-go` does not need editing: confirm via
      `grep -n '/draft-plan' skills/research-and-go/SKILL.md` that the
      file contains zero direct `/draft-plan` dispatches (all
      `/draft-plan` mentions are prose). Document this verification
      inline in this phase.
- [ ] Bump `metadata.version` in `skills/research-and-plan/SKILL.md` and
      `skills/run-plan/SKILL.md`. Two separate commits, each with its
      own bump dance (per the discipline table above).
- [ ] Mirror via `bash scripts/mirror-skill.sh research-and-plan` and
      `bash scripts/mirror-skill.sh run-plan`; verify
      `diff -rq skills/<name> .claude/skills/<name>` silent for both.

### Design & Constraints

#### Exact dispatch template edit (research-and-plan)

The current dispatch template at the `### Step 2 — Draft sub-plans`
section of `skills/research-and-plan/SKILL.md` reads (verified at the
draft time; implementing agent re-verifies):

```
3. Dispatch: `/draft-plan output <path> <sub-problem description>`
   - **If `LANDING_ARG` is non-empty**, append `. Landing mode: <LANDING_ARG>`
     to the description so `/draft-plan` can embed the matching hint in
     the generated plan. Example:
     `/draft-plan output $ZSKILLS_PLANS_DIR/X.md rounds 2 <description>. Landing mode: pr`
```

Note the inconsistency in the existing source: the **prose** says
`output <path> <sub-problem description>` (no rounds), but the
**example** has `rounds 2`. The implementing agent should treat both
the prose and the example as canonical insertion points and add
`parent=research-and-plan` to both, immediately after the
`output <path>` token (and after `rounds N` if present), and BEFORE
the `<description>`:

Prose form (after edit):

```
3. Dispatch: `/draft-plan output <path> parent=research-and-plan <sub-problem description>`
```

Example form (after edit):

```
/draft-plan output $ZSKILLS_PLANS_DIR/X.md rounds 2 parent=research-and-plan <description>. Landing mode: pr
```

#### Exact dispatch edit (run-plan, NEW)

The current `/run-plan` auto-mode staleness check dispatches
`/draft-plan <plan-file>` (verified at `skills/run-plan/SKILL.md` near
the `**Check for staleness**` work item). Add `parent=run-plan` as a
positional flag between the plan file and the description-suffix (if
any):

```
- With `auto`: dispatch `/draft-plan <plan-file> parent=run-plan` on the
  plan file to update it. `/draft-plan` handles existing files as
  modernizations (and the `parent=run-plan` token suppresses
  auto-worktree creation since `/run-plan` is already in its own
  worktree). After the refresh, re-read the plan and continue.
```

The `parent=run-plan` token MUST appear:
- After the plan file (positional flag).
- As a literal string `parent=run-plan` (lowercase, hyphenated,
  no spaces, no quoting) so Phase 1's parser recognition fires.

**No env-var export.** The token rides via the dispatch string. Do NOT
add `export ZSKILLS_PIPELINE_ID=...` or any other env mutation — banned
by `tests/test-skill-conformance.sh:1047-1052`.

#### Propagation chain (verified)

`/research-and-go` dispatches `/research-and-plan` only (verified by
`grep -n '/draft-plan' skills/research-and-go/SKILL.md` showing only
prose references — no actual dispatch). Chain:

```
/research-and-go → /research-and-plan (parent=research-and-go)
                    └─ /draft-plan (parent=research-and-plan)  [after Phase 2 edit]

/run-plan auto (textual staleness)
                    └─ /draft-plan <plan-file> parent=run-plan  [after Phase 2 edit]
```

Phase 1's gate accepts `parent=research-and-plan`, `parent=research-and-go`,
and `parent=run-plan` as recognized parent names. Plus the
`.zskills-tracked` SKIP catches any caller that creates a worktree
without remembering to emit the token (defense in depth).

#### Future skill-author note (closes D-F)

Any new skill that dispatches `/draft-plan` via the Skill tool or as a
slash-command-with-args inside a worktree MUST do ONE of:

1. Emit `parent=<own-name>` in the dispatch string (and add `<own-name>`
   to the recognized list in Phase 0's case statement).
2. Ensure `.zskills-tracked` is present in the worktree's toplevel (it
   already is, if the worktree was created via `create-worktree.sh`).

Add a paragraph to CLAUDE_TEMPLATE.md (out of scope for this plan as an
edit, but file an issue) documenting this. The `.zskills-tracked` SKIP
is the safety net; the explicit `parent=<name>` token is the polite
signal.

#### Skill-versioning bumps (mandatory — TWO separate commits)

```bash
# After research-and-plan edit:
( cd "$WT_PATH" && \
  today=$(TZ=America/New_York date +%Y.%m.%d) && \
  hash=$(bash scripts/skill-content-hash.sh skills/research-and-plan) && \
  bash scripts/frontmatter-set.sh skills/research-and-plan/SKILL.md metadata.version "$today+$hash" && \
  bash scripts/mirror-skill.sh research-and-plan && \
  diff -rq skills/research-and-plan .claude/skills/research-and-plan )

# After run-plan edit (separate commit):
( cd "$WT_PATH" && \
  today=$(TZ=America/New_York date +%Y.%m.%d) && \
  hash=$(bash scripts/skill-content-hash.sh skills/run-plan) && \
  bash scripts/frontmatter-set.sh skills/run-plan/SKILL.md metadata.version "$today+$hash" && \
  bash scripts/mirror-skill.sh run-plan && \
  diff -rq skills/run-plan .claude/skills/run-plan )
```

#### Hard constraints

- The tokens MUST be lowercase `parent=research-and-plan` and
  `parent=run-plan` exactly.
- No edits to `skills/research-and-go/SKILL.md`.
- `metadata.version` MUST bump in both edited skills (two separate
  commits, two separate bumps).
- Mirrors MUST be regenerated for both.

### Acceptance Criteria

- [ ] `grep -c 'parent=research-and-plan' skills/research-and-plan/SKILL.md` ≥ 2
      (both the prose form and the worked example).
- [ ] `grep -c 'parent=run-plan' skills/run-plan/SKILL.md` ≥ 1.
- [ ] The tokens appear inside their respective `/draft-plan` dispatch
      templates (not in unrelated prose).
- [ ] `bash tests/test-skill-conformance.sh` exits 0 after edits.
- [ ] `diff -rq skills/research-and-plan .claude/skills/research-and-plan`
      and `diff -rq skills/run-plan .claude/skills/run-plan` are silent.
- [ ] `skills/research-and-go/SKILL.md` is UNCHANGED.
- [ ] `grep -n '/draft-plan' skills/research-and-go/SKILL.md` shows only
      prose references (no dispatch lines starting with `/draft-plan` as
      a command), confirming r&g does not need editing.

### Dependencies

None — independent of Phase 1 in terms of compile order. Conformance
suite in Phase 3 verifies all three skill edits together.

---

## Phase 3 — Conformance test additions

### Goal

Extend `tests/test-skill-conformance.sh` with new assertions that lock
the Phase 1 + Phase 2 contract: (a) `/draft-plan` SKILL.md has the
Phase 0 heading, parser parent-token recognition, the five SKIP-
condition keywords, the state-file mechanism, and the parser→bash
handoff anchor; (b) Phase 6 has the auto-commit step with state-file
consume; (c) `/research-and-plan` and `/run-plan` dispatches contain
their respective `parent=...` tokens.

### Work Items

- [ ] Add a new section in `tests/test-skill-conformance.sh` AFTER the
      existing `/draft-plan`-specific block (search anchor:
      `=== /draft-plan & /research-and-plan — no PLAN_INDEX writes`)
      and BEFORE the `=== create-worktree.sh caller contract ===` block.
- [ ] Use the existing helper API: `check`, `check_fixed`, `check_not`,
      `check_in_file`, `check_executable`. **Do NOT use a hand-rolled
      `FAIL=1` accumulator** — the script's exit is gated on
      `FAIL_COUNT`, which the helpers manage. See "Assertion style"
      below.
- [ ] Bump the create-worktree caller-count guard. The actual variable
      is `PIPELINE_ID_CONTRACT_CALLS` (NOT `caller_count`). The current
      count of multi-line `create-worktree.sh` callers in `skills/` is
      8; after Phase 1 adds `/draft-plan` it becomes 9. The `< 6`
      threshold is a "scan-broken" floor, not a tight count — bumping
      to `< 7` is optional polish but **not required** for the new
      caller to be admitted. **Recommended:** leave the floor at `< 6`
      and add a NEW explicit assertion that the new `/draft-plan`
      caller invokes `create-worktree.sh` with
      `--pipeline-id "draft-plan.${TRACKING_ID}"` (positive-presence
      check using ERE so whitespace and `${VAR}`/`$VAR` variations
      pass — see "Whitespace-tolerant assertions" below).

### Design & Constraints

#### Assertion style — use the existing helpers

The conformance script defines:
- `pass <label>` / `fail <label> <pattern>`
- `check <skill> <label> <pattern>` — recursive grep -E
- `check_fixed <skill> <label> <literal>` — recursive grep -F
- `check_not <skill> <label> <pattern>` — recursive grep -E (negative)
- `check_in_file <skill> <relpath> <label> <pattern>` — single-file grep -E
- `check_not_in_file <skill> <relpath> <label> <pattern>` — single-file
  grep -E (negative)
- `check_executable <skill> <relpath> <label>`

All helpers auto-wire into `PASS_COUNT` / `FAIL_COUNT`. Setting `FAIL=1`
manually does NOT influence the exit code — it is dead code.

#### Whitespace-tolerant assertions (closes R-F4 / R-F10 / D-I)

`check_fixed` is `grep -rF` — literal-string match. It's brittle to:
- Whitespace variation (`--pipeline-id  "..."` with two spaces).
- `${VAR}` vs `$VAR` interpolation form.
- Quoting style.

For assertions on bash-fence patterns where these may legitimately vary,
use `check` (ERE) with explicit whitespace+brace classes. Examples
below.

#### Example new assertions (paste into the new conformance section)

```bash
echo ""
echo "=== /draft-plan auto-worktree + auto-commit (issue #226) ==="

# Phase 0 heading present
check_fixed draft-plan "auto-worktree Phase 0 heading" \
    '## Phase 0 — Worktree setup'

# Phase 0 fence-count assertion (NEW — closes DA-R3-F1).
# Phase 0's bash chunks MUST merge into a single ```bash ... ``` block
# in the final SKILL.md. Multiple fences would re-create the cross-fence
# variable-loss problem the state file is designed to solve cross-phase.
PHASE_0_BLOCK_COUNT=$(awk '
  /^## Phase 0 /{in_phase=1; next}
  /^## (Pre-check|Arguments|Phase [1-9])/{in_phase=0}
  in_phase && /^```bash$/{count++}
  END{print count+0}
' "$REPO_ROOT/skills/draft-plan/SKILL.md")
if [ "$PHASE_0_BLOCK_COUNT" -eq 1 ]; then
  pass "draft-plan Phase 0 is a single bash fence ($PHASE_0_BLOCK_COUNT)"
else
  fail "draft-plan Phase 0 must be a SINGLE bash fence (found $PHASE_0_BLOCK_COUNT)" \
       "single-fence assertion"
fi

# Parser→bash handoff anchor present (closes R-F3)
check_fixed draft-plan "parser→bash handoff prose anchor" \
    'Parser→bash handoff (orchestrator-emitted literal)'

# Gate keywords present (each as a separate assertion for granular failure messages)
check_fixed draft-plan "gate keyword: LANDING_HINT"     'LANDING_HINT'
check_fixed draft-plan "gate keyword: MAIN_PROTECTED"   'MAIN_PROTECTED'
check_fixed draft-plan "gate keyword: BRANCH_PREFIX"    'BRANCH_PREFIX'
check_fixed draft-plan "gate keyword: DELEGATED"        'DELEGATED'
check_fixed draft-plan "gate keyword: IN_WORKTREE"      'IN_WORKTREE'
check_fixed draft-plan "gate keyword: ALREADY_MANAGED"  'ALREADY_MANAGED'
# Trust-model guard: .zskills-tracked in MAIN must NOT trigger SKIP (closes DA-R3 F3).
check    draft-plan "ALREADY_MANAGED guarded by TOPLEVEL!=MAIN_ROOT" \
    '\$TOPLEVEL"[[:space:]]*!=[[:space:]]*"\$MAIN_ROOT|TOPLEVEL.*!=.*MAIN_ROOT'
check_fixed draft-plan "gate keyword: DRAFT_PLAN_PARENT" 'DRAFT_PLAN_PARENT'

# Whitespace-tolerant: --pipeline-id "draft-plan.${TRACKING_ID}" (closes R-F10)
check    draft-plan "create-worktree --pipeline-id" \
    '--pipeline-id[[:space:]]+"draft-plan\.\$\{?TRACKING_ID\}?"'

# Whitespace-tolerant: --branch-name uses $BRANCH_PREFIX (closes D-C)
check    draft-plan "create-worktree --branch-name uses BRANCH_PREFIX" \
    '--branch-name[[:space:]]+"\$\{?BRANCH_PREFIX\}?\$\{?TRACKING_ID\}?"'

check_fixed draft-plan "create-worktree --allow-resume" '--allow-resume'

# Arguments parser recognizes parent=<name> incl. run-plan; ERE form (closes R-F4)
check    draft-plan "Arguments mentions parent= token incl. run-plan" \
    'parent=<name>|parent=(research-and-plan|research-and-go|run-plan)'
check    draft-plan "Arguments mentions strip the parent= token" \
    'strip|stripped'

# Phase 0's STOP-on-failure prose
check_fixed draft-plan "Phase 0 STOP-on-failure prose" \
    'STOP `/draft-plan` immediately'

# State-file mechanism (closes R-F1 / R-F5 / R-F6)
check_fixed draft-plan "state-file write template" \
    'STATE_FILE="/tmp/zskills-draftplan-state-'
check    draft-plan "state-file consume pattern" \
    '\[ -f "\$STATE_FILE" \] && \. "\$STATE_FILE"'

# Phase 6 step 2.5 auto-commit assertions
check    draft-plan "auto-commit git add via -C" \
    'git -C "\$WT_PATH" add'
check    draft-plan "auto-commit git commit via -C" \
    'git -C "\$WT_PATH" commit'
check_fixed draft-plan "auto-commit no-op guard" \
    'plan file unchanged from HEAD'
check_fixed draft-plan "auto-commit staged-set defense" \
    'unexpected staged set'
# Whitespace+brace-tolerant trailer assertion (closes D-I)
check    draft-plan "auto-commit --trailer form" \
    '--trailer[[:space:]]+"Co-Authored-By:[[:space:]]+\$\{?COMMIT_CO_AUTHOR\}?"'

# Phase 6 step 2 references $OUTPUT_FILE_ABS
check_fixed draft-plan "step 2 references OUTPUT_FILE_ABS" \
    '$OUTPUT_FILE_ABS'

# Phase 6 step 4 report template surfaces worktree/branch/commit
check_fixed draft-plan "report: Worktree label" 'Worktree:'
check_fixed draft-plan "report: Branch label"   'Branch:'
check_fixed draft-plan "report: Commit label"   'Commit:'

# Argument-hint frontmatter advertises parent=<name>
check_in_file draft-plan SKILL.md "argument-hint advertises parent=" \
    'argument-hint:.*\[parent=<name>\]'

# /research-and-plan emits parent=research-and-plan in its /draft-plan dispatch
check_fixed research-and-plan "dispatch token: parent=research-and-plan" \
    'parent=research-and-plan'

# /run-plan emits parent=run-plan in its /draft-plan refresh dispatch (closes D-B)
check_fixed run-plan "dispatch token: parent=run-plan" \
    'parent=run-plan'

# Negative: no git push in command position (anchored at line start, ignoring leading whitespace)
check_not draft-plan "no git push command" \
    '^[[:space:]]*git[[:space:]]+push'
check_not draft-plan "no gh pr create" '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+create'
check_not draft-plan "no gh pr merge"  '^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge'

# Existing ban (already present in the file as the global check at :1047);
# duplicate here for symmetry and granular failure messages.
check_not draft-plan "no export ZSKILLS_PIPELINE_ID" \
    'export[[:space:]]+ZSKILLS_PIPELINE_ID'

# Skill version format — date prefix + content hash, asserted on all three edited skills
check_in_file draft-plan SKILL.md "metadata.version format (draft-plan)" \
    '^  version: "[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[a-f0-9]{6}"'
check_in_file research-and-plan SKILL.md "metadata.version format (research-and-plan)" \
    '^  version: "[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[a-f0-9]{6}"'
check_in_file run-plan SKILL.md "metadata.version format (run-plan)" \
    '^  version: "[0-9]{4}\.[0-9]{2}\.[0-9]{2}\+[a-f0-9]{6}"'
```

#### `git push` regex is command-position-only

The plan body itself contains prose mentions like "No `git push`" in
constraint sections. A naive regex `git[[:space:]]+push` would
false-positive on those. The anchored regex
`^[[:space:]]*git[[:space:]]+push` requires the match at the start of
a line (optionally indented), excluding inline-code spans like
`` `git push` `` and prose mentions inside paragraphs.

#### Caller-count guard treatment (final)

Per the rationale above, **do not bump the `< 6` floor**. Add the
explicit `--pipeline-id` ERE presence check instead.

#### Hard constraints

- Assertions MUST use the existing `check_*` / `check_not_*` helpers.
  No hand-rolled `FAIL=1` accumulator.
- Negative regexes that scan plan-prose-heavy files MUST anchor at
  line-start to avoid prose false-positives.
- Whitespace-sensitive assertions on bash-fence patterns MUST use
  `check` (ERE) with `[[:space:]]+` between tokens and `\$\{?VAR\}?`
  for variables, NOT `check_fixed` (closes R-F10 / D-I).
- No new dependencies (no jq, no python — just grep, sed, and bash).
- Do NOT modify or delete existing assertions in this file.

### Acceptance Criteria

- [ ] `bash tests/test-skill-conformance.sh` exits 0 after Phases 1+2
      are implemented and Phase 3's assertions are added.
- [ ] Mutation test: revert one of the Phase 1 edits (e.g. remove the
      `## Phase 0 — Worktree setup` heading) and confirm
      `bash tests/test-skill-conformance.sh` exits non-zero with the
      corresponding FAIL line. Restore after.
- [ ] Mutation test: remove `parent=research-and-plan` from
      `skills/research-and-plan/SKILL.md` and confirm conformance fails.
      Restore after.
- [ ] Mutation test: remove `parent=run-plan` from
      `skills/run-plan/SKILL.md` and confirm conformance fails.
      Restore after.
- [ ] Negative assertion for `git push` does NOT false-positive on the
      prose mentions inside the new Phase 0 / Phase 6 constraint
      sections (verified by running conformance once with the new
      assertions and observing the PASS line).
- [ ] The whitespace-tolerant `--pipeline-id` ERE assertion matches
      Phase 1's canonical block AND would still match if the
      implementing agent uses two spaces or `${TRACKING_ID}` braces.
      Spot-check by editing the SKILL.md to `"draft-plan.${TRACKING_ID}"`
      (curly form) and confirming the assertion still passes.
- [ ] No existing conformance assertions were modified or deleted.

### Dependencies

Requires Phase 1 (the assertions in Phase 3 target Phase 1's edits) and
Phase 2 (the `parent=...` token assertions target Phase 2's edits).

---

## Phase 4 — Canary: pure-shell gate fixture

### Goal

Add a new pure-shell canary `tests/canary-draft-plan-auto-worktree.sh`
that exercises Phase 1's auto-worktree gate logic with fixture
configurations WITHOUT actually creating worktrees (the canary tests
the **decision tree**, not `create-worktree.sh`).

### Work Items

- [ ] Create `tests/canary-draft-plan-auto-worktree.sh` (executable,
      `chmod +x`, `#!/usr/bin/env bash`, `set -euo pipefail`).
- [ ] Implement the gate logic as a sourceable bash function
      `gate_would_create`, paste-equivalent of Phase 1's gate. Inputs:
      `CONFIG_FILE`, `DRAFT_PLAN_PARENT`, `ZSKILLS_PIPELINE_ID`,
      `IN_WORKTREE`, `ALREADY_MANAGED`. Returns 0 (would-create) /
      1 (SKIP).
- [ ] Implement seven distinct test cases (case 1 positive + cases 2-7
      SKIPs; **no duplicate cases** — closes D-E).
- [ ] Wire the canary into `tests/run-all.sh` via `run_suite` (NOT bare
      `bash`). Use a **structural anchor** (search for an existing
      `run_suite "canary-` line), NOT a fixed line number (closes
      R-F11). Insertion can be at the end of the canary block.
- [ ] Verify the canary exits 0 in a clean run.

### Design & Constraints

#### Canary template

```bash
#!/usr/bin/env bash
# tests/canary-draft-plan-auto-worktree.sh
#
# Exercises the /draft-plan Phase 0 auto-worktree gate decision logic
# with fixture configurations. Does NOT call create-worktree.sh —
# tests the DECISION, not the side effect.

set -euo pipefail

PASS=0
FAIL=0
TMP=$(mktemp -d -t draftplan-canary.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# The gate function — paste-equivalent of Phase 0's bash.
gate_would_create() {
  local CONFIG_FILE="$1"
  local DRAFT_PLAN_PARENT_LOCAL="$2"
  local ZSKILLS_PIPELINE_ID_LOCAL="$3"
  local IN_WORKTREE_LOCAL="$4"
  local ALREADY_MANAGED_LOCAL="$5"

  local LANDING_HINT=""
  local MAIN_PROTECTED="false"
  if [ -f "$CONFIG_FILE" ]; then
    local CONFIG_CONTENT
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    if [[ "$CONFIG_CONTENT" =~ \"landing\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
      LANDING_HINT="${BASH_REMATCH[1]}"
    fi
    if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*(true|false) ]]; then
      MAIN_PROTECTED="${BASH_REMATCH[1]}"
    fi
  fi

  local DELEGATED=0
  if [ -n "$ZSKILLS_PIPELINE_ID_LOCAL" ]; then
    DELEGATED=1
  elif [ -n "$DRAFT_PLAN_PARENT_LOCAL" ]; then
    case "$DRAFT_PLAN_PARENT_LOCAL" in
      research-and-plan|research-and-go|run-plan) DELEGATED=1 ;;
    esac
  fi

  if [ "$LANDING_HINT" != "pr" ] \
     || [ "$MAIN_PROTECTED" != "true" ] \
     || [ "$DELEGATED" = "1" ] \
     || [ "$IN_WORKTREE_LOCAL" = "1" ] \
     || [ "$ALREADY_MANAGED_LOCAL" = "1" ]; then
    return 1   # SKIP
  fi
  return 0     # would-create
}

assert_create() {
  local name="$1"; shift
  if gate_would_create "$@"; then
    PASS=$((PASS+1))
    echo "PASS: $name (would-create)"
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name expected would-create, got SKIP"
  fi
}

assert_skip() {
  local name="$1"; shift
  if ! gate_would_create "$@"; then
    PASS=$((PASS+1))
    echo "PASS: $name (SKIP)"
  else
    FAIL=$((FAIL+1))
    echo "FAIL: $name expected SKIP, got would-create"
  fi
}

# Fixtures
cat > "$TMP/pr_protected.json" <<'JSON'
{"execution":{"landing":"pr","main_protected":true}}
JSON
cat > "$TMP/pr_unprotected.json" <<'JSON'
{"execution":{"landing":"pr","main_protected":false}}
JSON
cat > "$TMP/cherrypick.json" <<'JSON'
{"execution":{"landing":"cherry-pick","main_protected":true}}
JSON

# Case 1: PR + protected + standalone + not-in-worktree + not-managed → would-create
assert_create "pr+protected+standalone+main" \
  "$TMP/pr_protected.json" "" "" "0" "0"

# Case 2: landing=cherry-pick → SKIP
assert_skip "cherry-pick → SKIP" \
  "$TMP/cherrypick.json" "" "" "0" "0"

# Case 3: main_protected=false → SKIP
assert_skip "main_protected=false → SKIP" \
  "$TMP/pr_unprotected.json" "" "" "0" "0"

# Case 4: in-worktree=1 → SKIP
assert_skip "in-worktree → SKIP" \
  "$TMP/pr_protected.json" "" "" "1" "0"

# Case 5a: delegated via ZSKILLS_PIPELINE_ID env → SKIP
assert_skip "delegated via env → SKIP" \
  "$TMP/pr_protected.json" "" "draft-plan.foo" "0" "0"

# Case 5b: delegated via DRAFT_PLAN_PARENT=research-and-plan → SKIP
assert_skip "delegated via parent=research-and-plan → SKIP" \
  "$TMP/pr_protected.json" "research-and-plan" "" "0" "0"

# Case 5c: delegated via DRAFT_PLAN_PARENT=research-and-go → SKIP
assert_skip "delegated via parent=research-and-go → SKIP" \
  "$TMP/pr_protected.json" "research-and-go" "" "0" "0"

# Case 5d: delegated via DRAFT_PLAN_PARENT=run-plan → SKIP (closes D-B)
assert_skip "delegated via parent=run-plan → SKIP" \
  "$TMP/pr_protected.json" "run-plan" "" "0" "0"

# Case 6: ALREADY_MANAGED=1 (.zskills-tracked present) → SKIP (closes D-B safety net)
# Distinct from case 4: case 4 is "git rev-parse says we're in a
# worktree"; case 6 is "we're in MAIN's cwd but the toplevel has
# .zskills-tracked", which catches callers that don't set
# parent=<name> but DO create their own worktree (e.g., a future
# skill or /do/-fix-issues invocation chain).
assert_skip "already-managed (.zskills-tracked present) → SKIP" \
  "$TMP/pr_protected.json" "" "" "0" "1"

# Case 7: unrecognized parent name → would-create (defensive — the gate
# only SKIPs on KNOWN parent names; an unknown one is treated as
# user-supplied description noise, NOT as a delegation signal).
assert_create "unrecognized parent name → would-create" \
  "$TMP/pr_protected.json" "some-other-skill" "" "0" "0"

# Results
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
```

**Total: 9 PASS lines on clean run** (cases 1, 2, 3, 4, 5a, 5b, 5c, 5d,
6, 7 → 10 cases; case 1 + cases 2-4 (3) + cases 5a/5b/5c/5d (4) + case
6 + case 7 = **10 PASS lines** — recount: 1+3+4+1+1 = 10).

Recount table (closes D-E — every case is distinct at the gate level):

| Case | Distinguishing input | Expected | Distinct from |
|------|---------------------|----------|---------------|
| 1 | pr_protected, all signals empty/0 | create | (baseline) |
| 2 | cherrypick.json | SKIP | case 1 (landing) |
| 3 | pr_unprotected.json | SKIP | case 1 (main_protected) |
| 4 | IN_WORKTREE=1 | SKIP | case 1 (in_worktree) |
| 5a | ZSKILLS_PIPELINE_ID set | SKIP | case 1 (env delegation) |
| 5b | parent=research-and-plan | SKIP | case 1 (parser delegation) |
| 5c | parent=research-and-go | SKIP | case 1 (parser delegation, future-proof arm) |
| 5d | parent=run-plan | SKIP | case 1 (NEW — closes D-B) |
| 6 | ALREADY_MANAGED=1 | SKIP | case 1 (.zskills-tracked) |
| 7 | parent=some-other-skill | create | case 5b (unknown name → not SKIP) |

10 cases, 10 distinct gate inputs, 10 PASS lines. AC8's expected PASS
count is **10**.

#### Trust-model note (NEW — closes DA-R3 F3)

The `ALREADY_MANAGED` input to `gate_would_create` is computed UPSTREAM
in the real SKILL.md as `[ -f "$TOPLEVEL/.zskills-tracked" ] && [
"$TOPLEVEL" != "$MAIN_ROOT" ]` — i.e., the file must be in a worktree
that is NOT MAIN. This canary takes the boolean as a parameter (cases
6 and 1 distinguish `ALREADY_MANAGED=1` vs `0`); the trust-model guard
(MAIN-not-trusted) is enforced in Phase 0's bash and asserted by Phase
3's `[ "$TOPLEVEL" != "$MAIN_ROOT" ]` conformance keyword check.

#### Lockstep with the skill (acknowledged)

The canary's `gate_would_create` is a hand-translation of Phase 1's bash.
Mechanical lockstep via a sourceable script was rejected: the gate is
small (~35 lines) and stable; extracting bash from prose into a sidecar
script is a larger architecture shift than this plan justifies.
Phase 3 includes a conformance keyword-scan over the canary
(`LANDING_HINT`, `MAIN_PROTECTED`, `DRAFT_PLAN_PARENT`,
`ALREADY_MANAGED`, etc.) to catch gross drift; semantic drift surfaces
in canary case failures at refactor time. Future gate-condition
additions must update the canary alongside the skill.

#### Wire into the test runner (structural anchor — closes R-F11)

`tests/run-all.sh` uses a `run_suite <name> <script>` function. Add this
line near the other `run_suite "canary-..."` entries (search anchor:
`run_suite "canary-` — pick the last such line and insert after it):

```bash
run_suite "canary-draft-plan-auto-worktree.sh" "tests/canary-draft-plan-auto-worktree.sh"
```

A bare `bash tests/canary-draft-plan-auto-worktree.sh` (without
`run_suite`) would execute but its result would NOT be tallied. Use
`run_suite` exactly.

#### Hard constraints

- The canary MUST be **pure shell**: no python, no node, no jq.
- The canary MUST NOT call `bash scripts/create-worktree.sh` or invoke
  any real git operation beyond what's in `$TMP`.
- The canary MUST clean up `$TMP` via the EXIT trap.
- The canary MUST exit 0 on success and non-zero on any failure.
- The gate-function bash MUST be semantically equivalent to the
  Phase 1 SKILL.md bash. Phase 3 includes a conformance assertion that
  scans the canary for each gate keyword to catch drift.
- Mark the canary executable (`chmod +x`) before committing.

### Acceptance Criteria

- [ ] `bash tests/canary-draft-plan-auto-worktree.sh` exits 0 with
      10 `PASS:` lines and 0 `FAIL:` lines.
- [ ] Mutation test: change one fixture (e.g. set `landing` to `pr` in
      `cherrypick.json`) and confirm the canary exits non-zero with the
      expected `FAIL:` line. Restore the fixture.
- [ ] `tests/canary-draft-plan-auto-worktree.sh` is executable
      (`test -x tests/canary-draft-plan-auto-worktree.sh`).
- [ ] The canary is wired into `tests/run-all.sh` via `run_suite
      "canary-draft-plan-auto-worktree.sh" ...`. The insertion point
      is at the end of the existing `run_suite "canary-..."` block
      (structural anchor, not line number).
- [ ] `ls /tmp/draftplan-canary.* 2>/dev/null` returns no leftover dirs
      after a clean run (EXIT trap works).

### Dependencies

Independent of other phases for development, but conceptually mirrors
Phase 1's gate logic — if Phase 1's gate changes, this canary needs
updating. Run order: implement Phase 1 first, then write the canary
copying Phase 1's bash verbatim.

---

## Phase 5 — Full verification & manual smoke

### Goal

Run the full conformance + canary + test-runner suite, then perform a
manual smoke test exercising the auto-worktree + auto-commit flow
end-to-end with a real config swap. Roll up issue #226's 7 stated ACs
plus the canary AC promoted from optional to required (AC8) here.

### Work Items

- [ ] Run `bash tests/test-skill-conformance.sh` — exit 0 required.
- [ ] Run `bash tests/canary-draft-plan-auto-worktree.sh` — exit 0 required.
- [ ] Run `bash tests/run-all.sh` — exit 0 required.
- [ ] **Manual smoke test #1 — PR + protected (positive case, MANDATORY):**
    1. Confirm `.claude/zskills-config.json` has `landing: pr` and
       `main_protected: true` (it already does in this repo).
    2. From a clean main checkout in this repo, invoke `/draft-plan`
       with a UNIQUE time-stamped slug (closes D-K — avoids
       accumulating stale `feat/smoke-test` worktrees across runs):
       ```
       SMOKE_SLUG="SMOKE_TEST_$(date +%s)"
       /draft-plan ${SMOKE_SLUG}.md rounds 1 test description
       ```
    3. Verify: worktree exists at `/tmp/zskills-draftplan-<slug>`,
       branch `${BRANCH_PREFIX}<slug>` exists (i.e., `feat/smoke-test-<ts>`),
       single commit `docs(plans): draft <SLUG> — ...` is at HEAD with
       no literal `<one-liner>` placeholder in the subject, final
       report lists worktree path + branch + commit SHA.
    4. **Cleanup is the user's call.** Write a `.landed` marker with
       `status: not-landed`, source `draft-plan smoke #1` per
       CLAUDE.md L113-120; present the worktree state to the user
       and ASK whether to remove it. Do NOT auto-`--force`-remove. If
       the user says remove, do BOTH `git worktree remove "$WT_PATH"`
       AND `git branch -D ${BRANCH_PREFIX}${SMOKE_SLUG}` — both with
       error visibility (no `2>/dev/null`, no `; echo done`).
- [ ] **Manual smoke test #2 — cherry-pick mode (negative case, MANDATORY):**
      Temporarily flip `landing` to `cherry-pick` in a working-tree copy
      of the config, invoke `/draft-plan` standalone, verify NO worktree
      is created and the plan file lands in main's working tree
      uncommitted (today's behavior). Restore config.
- [ ] **Manual smoke test #3 — delegated via /research-and-plan (RECOMMENDED, skippable):**
      `/research-and-plan` is a heavy multi-round skill (5-20 min).
      Phase 4 canary cases 5a/5b/5c/5d already cover the delegation
      SKIP detection deterministically. Run this smoke only if Phase 4
      canary cases 5b and 5d both passed; if skipped, document the
      rationale in the Phase 5 report. If run: invoke
      `/research-and-plan` with a small description; verify it
      dispatches `/draft-plan` with `parent=research-and-plan` in the
      dispatch string and that `/draft-plan` does NOT auto-create a
      second worktree.
- [ ] **Manual smoke test #4 — /run-plan auto refresh chain (NEW,
      MANDATORY — closes D-B):**
      1. Pick any pre-existing PR-mode plan file with `## Dependencies`
         containing the phrase "drafted before".
      2. Invoke `/run-plan auto` on that plan from MAIN.
      3. Verify: `/run-plan` creates its own worktree (its standard
         flow), then dispatches `/draft-plan <plan-file>
         parent=run-plan`. `/draft-plan` SKIPS auto-worktree (because
         `parent=run-plan` is recognized AND `.zskills-tracked` is
         present in `/run-plan`'s worktree). The refresh writes back
         to the same plan file path. `/run-plan` resumes against the
         refreshed plan. **Critical:** verify only ONE worktree exists
         under `/tmp/` for the plan slug — NOT two.

### Design & Constraints

#### Manual smoke procedure

Smoke test #1 is the load-bearing one. Capture test output to a file
per CLAUDE.md ("Capture test output to a file, never pipe"):

```bash
TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
mkdir -p "$TEST_OUT"
bash tests/test-skill-conformance.sh > "$TEST_OUT/.conformance.txt" 2>&1
bash tests/canary-draft-plan-auto-worktree.sh > "$TEST_OUT/.canary.txt" 2>&1
bash tests/run-all.sh > "$TEST_OUT/.runall.txt" 2>&1
```

Then read the `.txt` files for failures.

#### Verifier dispatch (per CLAUDE.md "Verifier-cannot-run rule")

The verifier subagent MUST run the tests inline (no `run_in_background:
true` + `Monitor` anti-pattern). Layer 0
(`.claude/hooks/inject-bash-timeout.sh`) extends the default Bash
timeout to 600000 ms so the 120s default doesn't trigger the bg-mode
reflex. If the verifier returns matching one of the 7 stalled-string
phrases or fails the 200-byte minimum-length signal, treat as
**verification FAIL** — invoke the Failure Protocol, do not do inline
self-verification.

#### Worktree-rules compliance

CLAUDE.md "Worktree Rules": "NEVER remove worktrees that contain
changes" without explicit user approval. Smoke test #1 creates a
worktree with one commit. Plan does NOT `--force` remove it. Instead:

1. Write `.landed` marker with:
   ```
   status: not-landed
   date: <timestamp>
   source: draft-plan smoke #1
   ```
2. Present a one-line summary to the user listing the worktree path,
   branch, and commit hash.
3. Let the user choose to remove the worktree or land/inspect it.

The unique time-stamped slug (D-K fix) ensures re-runs don't collide
with leftover smoke-test worktrees from prior runs.

#### No-push / no-PR rule

This plan does NOT push, does NOT create a PR. Final state after
Phase 5 is: feature branch exists locally on this plan's own worktree
with phase commits + the auto-committed plan file. User chooses to
land via `/commit pr auto` after `/run-plan` completes.

#### Hard constraints

- All three test commands MUST exit 0. Pre-existing failures unrelated
  to this plan's edits may be flagged with a GitHub issue per CLAUDE.md
  ("Pre-existing test failures"), but every failure must be classified
  as pre-existing-and-filed OR fixed-now.
- Manual smoke tests #1, #2, and #4 MUST be performed (not just
  reasoned about). If a smoke can't run in the implementation
  environment, mark Phase 5 as blocked and surface to the user.
- Worktree cleanup after smoke is the **user's decision**; the plan
  writes a `.landed: not-landed` marker and ASKS — never
  `git worktree remove --force` unprompted.
- Do NOT auto-merge `/draft-plan`'s own draft worktree into main as
  part of Phase 5 — landing is the user's call.

### Acceptance Criteria

This phase rolls up issue #226's 7 stated ACs (AC1-AC7) plus the canary
AC promoted from "optional" to required (AC8), plus a new AC for the
/run-plan refresh chain (AC9):

- [ ] **AC1 (issue #226)** — In a PR-mode + main-protected project,
      standalone `/draft-plan <description>` creates a worktree on
      `${BRANCH_PREFIX}<plan-slug>`, writes the plan there, commits the
      plan as a single commit with a real (non-placeholder) subject.
      Final report includes worktree path + branch name + commit hash.
      Verified by manual smoke test #1.
- [ ] **AC2 (issue #226)** — When `/draft-plan` is invoked from
      `/research-and-plan` (delegated), auto-worktree path is SKIPPED.
      Verified by canary cases 5a/5b/5c/5d + manual smoke test #3 if run.
- [ ] **AC3 (issue #226)** — When orchestrator is already inside a
      worktree, auto-worktree path is SKIPPED. Verified by canary case 4.
- [ ] **AC4 (issue #226)** — When project has `execution.landing:
      cherry-pick` or `direct`, auto-worktree path is SKIPPED. Verified
      by manual smoke test #2 + canary case 2.
- [ ] **AC5 (issue #226)** — Phase 6 commit step runs in any worktree
      context (auto-created or pre-existing). Pre-existing context
      verified by re-running `/draft-plan` on this same plan from within
      this worktree: the no-op guard emits "plan file unchanged from
      HEAD; skipping auto-commit" and exits 0 (no spurious failure).
- [ ] **AC6 (issue #226)** — `metadata.version` bumped for
      `skills/draft-plan/SKILL.md` (Phase 1),
      `skills/research-and-plan/SKILL.md` (Phase 2), AND
      `skills/run-plan/SKILL.md` (Phase 2 NEW), with
      `.claude/skills/*` mirror regenerated for all three. Verified by
      `diff -rq` silent for all three skill dirs AND Phase 3 conformance
      assertion `metadata.version format` for each.
- [ ] **AC7 (issue #226)** — Conformance tests pass:
      `bash tests/test-skill-conformance.sh` exits 0.
- [ ] **AC8 (canary, promoted to required)** —
      `bash tests/canary-draft-plan-auto-worktree.sh` exits 0 with 10
      PASS lines and 0 FAIL lines.
- [ ] **AC9 (NEW — closes D-B)** — `/run-plan auto` refresh chain
      produces exactly ONE worktree (not two) for the refreshed plan
      slug. Verified by manual smoke test #4.
- [ ] **AC-roll-up** — `bash tests/run-all.sh` exits 0.
- [ ] **AC-roll-up** — Manual smoke tests #1, #2, and #4 (MANDATORY)
      pass with observed evidence (worktree path, branch, commit SHA
      captured for smoke #1; non-creation confirmed for #2; one-worktree
      invariant confirmed for #4). Smoke #3 is recommended but
      skippable if canary cases 5b and 5d passed.

### Dependencies

Requires Phases 1, 2, 3, 4 all complete.

---

## Plan Quality

**Drafting process:** /draft-plan with 3 rounds of adversarial review.

**Convergence:** Max rounds reached (3); orchestrator declared
convergence at R3. R3 surfaced 1 CRITICAL (DA F1, Phase 0 multi-fence)
— fixed in v4 via single-fence declaration + Phase 3 fence-count
conformance assertion. Zero R3 findings deferred.

**Remaining concerns (Justified, not Fixed in v4):**

- R3-R-F5 — `metadata.version` regex doesn't enforce today's date.
  CI's `skill-version-stage-check.sh` is the freshness backstop.
- R3-R-F6 — parser STRIP is LLM-behavioral; bracketed by Phase 3
  keyword scan + canary case 7.
- R3-R-F7 — plan length growth (positive audit); every line closes
  a specific finding.
- R3-D-F4 — concurrent same-slug runs documented as unsupported;
  staged-set defense bounds the damage.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved (Fixed/Justified) |
|-------|-------------------|---------------------------|----------------------------|
| 1     | 20                | 17                        | 35 / 2 |
| 2     | 12                | 11                        | 20 / 3 |
| 3     | 8                 | 5                         | 9 / 4  |

**Trajectory.** CRITICALs R1=3 → R2=4 → R3=1. Total findings 37 → 23
→ 13. Strictly downward on severity and total; all CRITICALs addressed.

---

## Round 1 Disposition

37 R1 findings (35 Fixed, 2 Justified). R2-flagged regressions are
marked `[REG]` and re-fixed in v3 — see R2 table.

| # | Finding | Sev | Src | Disposition |
|---|---------|-----|-----|-------------|
| R1 | Phase 6 line numbers brittle | MAJOR | R | Fixed — structural anchors |
| R2 | `$OUTPUT_FILE` prose-only | CRITICAL | R | Fixed — OUTPUT_FILE_* conventions section. **[REG]** R-F2/R-F3 re-fix via parser→bash handoff + unconditional `derive_output_paths` |
| R3 | Caller-count var name | MINOR | R | Fixed — Phase 3 cites `PIPELINE_ID_CONTRACT_CALLS` |
| R4 | Assertion style | MAJOR | R | Fixed — uses `check_*` helpers |
| R5 | `run-all.sh` wires via `run_suite` | MAJOR | R | Fixed. **[REG]** R-F11 re-fix via structural anchor |
| R6 | r&g propagation rationale | MAJOR | R | Fixed — Phase 2 D&C |
| R7 | Pre-check race on resume | MAJOR | R | Fixed — post-creation re-Pre-check + v3 adds D-H cp-seed |
| R8 | OUTPUT_FILE_REL conditional | MAJOR | R | Fixed — unconditional derivation. **[REG]** R-F1 re-fix via state file |
| R9 | co_author regex | MINOR | R | Justified — sources `zskills-resolve-config.sh` |
| R10 | parent= swallowed as description | MAJOR | R | Fixed — explicit parser STRIPPING |
| R11 | Canary doesn't exercise rc routing | MINOR | R | Justified — `test-create-worktree.sh` covers rc |
| R12 | TRACKING_ID slug regex | MINOR | R | Fixed — pre-validate before invocation |
| R13 | bump-dance bullet incomplete | MINOR | R | Fixed — 3-line block inline |
| R14 | AC5 no-op vs staged-set | MAJOR | R | Fixed — three-branch logic |
| R15 | r&g coverage missing | MINOR | R | Fixed — grep verification inline in Phase 2 |
| R16 | `git push` regex false-positives | MINOR | R | Fixed — anchored regex |
| R17 | "NO `cd`" overly broad | MINOR | R | Fixed — subshell forms allowed |
| R18 | OUTPUT_FILE_ABS not threaded | MAJOR | R | Fixed — Phase 6 step 2 amendment |
| R19 | Smoke #3 heavy | MINOR | R | Fixed — recommended/skippable |
| R20 | "8 ACs" wording | MINOR | R | Fixed — AC1-AC7 + AC8; v3 adds AC9 |
| D1 | parent= leaks | CRITICAL | DA | Fixed — STRIPPING |
| D2 | Substring grep false-positives | MAJOR | DA | Fixed — gate reads parser var |
| D3 | OUTPUT_FILE_REL fabricated | CRITICAL | DA | Fixed — `realpath --relative-to`. **[REG]** R-F2 re-fix via unconditional helper |
| D4 | Pre-check ordering | MAJOR | DA | Fixed (same as R7) |
| D5 | caller_count fabricated | MAJOR | DA | Fixed — correct var name |
| D6 | Auto-commit no-op fail | MAJOR | DA | Fixed (same as R14) |
| D7 | `<one-liner>` placeholder | MAJOR | DA | Fixed — `$ONELINER` derivation |
| D8 | Multi-commit bump discipline | MAJOR | DA | Fixed — table. **[REG]** D-A re-fix — hook documented as no-op, enforcement via discipline+CI |
| D9 | `$CLAUDE_PROJECT_DIR` semantics | MINOR | DA | Fixed — Phase 0 D&C clarifies |
| D10 | Canary bit-rots | MAJOR | DA | Justified — "Lockstep" section |
| D11 | `git push` prose false-positives | MINOR | DA | Fixed (same as R16) |
| D12 | `exit $RC` doesn't halt | MAJOR | DA | Fixed — mandatory STOP prose |
| D13 | r&g dead arm | MINOR | DA | Fixed — Phase 2 D&C propagation chain |
| D14 | Phase 2 `rounds N` ordering | MINOR | DA | Fixed — both insertion points |
| D15 | `--trailer` form | MINOR | DA | Fixed — verified at commit/SKILL.md:347-353 |
| D16 | metadata.version format | MINOR | DA | Fixed — Phase 3 grep assertion |
| D17 | Smoke `--force` | MINOR | DA | Fixed — `.landed: not-landed` + ASK |

**Totals (round 1):** 37 addressed (35 Fixed, 2 Justified); 5
re-fixed in v3: R2, R5, R8, D3, D8.

---

## Round 2 Disposition

Round 2: 12 reviewer + 11 DA findings; 4 CRITICALs total. Root causes:
(1) one-shot bash fence variable persistence — fixed via state-file
mechanism; (2) `block-stale-skill-version.sh` reads MAIN's index —
documented as no-op with subshell-`cd` mitigation + CI backstop.

| # | Finding | Sev | Src | Disposition |
|---|---------|-----|-----|-------------|
| R-F1 | Step 2.5 cwd-detection contradicts no-cd rule | CRITICAL | R | Fixed — step 2.5 sources state file, gates on `IN_WORKTREE`/`AUTO_WORKTREE_CREATED`; `WT_PATH="$TOPLEVEL"` removed |
| R-F2 | `OUTPUT_FILE_REL` unconditional in prose but conditional in bash | CRITICAL | R | Fixed — `derive_output_paths` called unconditionally pre-gate, again post-create; persisted via state file |
| R-F3 | `$OUTPUT_FILE` / `$DRAFT_PLAN_PARENT` parser→bash gap | MAJOR | R | Fixed — explicit "Parser→bash handoff" anchor; orchestrator-LLM emits literal assignments; Phase 3 asserts the anchor |
| R-F4 | Conformance regex mixes ERE/BRE | MINOR | R | Fixed — proper ERE alternation; adds `run-plan` per D-B |
| R-F5 | "exports" prose but no actual export | MAJOR | R | Fixed — replaced with state-file persistence; Phase 3 asserts write+consume patterns |
| R-F6 | Step 2.5 reassigns `WT_PATH` | MAJOR | R | Fixed — same as R-F1; reassignment removed |
| R-F7 | D17 sample passes | MINOR | R | Justified — positive sample |
| R-F8 | R10 sample: parser strip is doc-only | MINOR | R | Justified — strip is LLM-behavioral; bracketed by Phase 3 keyword scan + canary case 7 |
| R-F9 | "Supersedes" wrong direction | MINOR | R | Fixed — reworded to "COMPLEMENT each other; neither supersedes" |
| R-F10 | `check_fixed --pipeline-id` whitespace-brittle | MINOR | R | Fixed — switched to ERE with `[[:space:]]+` and `\$\{?VAR\}?`; applied to `--branch-name` and `--trailer` |
| R-F11 | `run-all.sh:43-45` line cite brittle | MINOR | R | Fixed — uses structural anchor `run_suite "canary-` instead |
| R-F12 | Bump dance + commit foreign-cwd hits hook | MINOR | R | Fixed — subshell-`cd` mitigation; "Hook composition" D&C section documents no-op + shifts enforcement to discipline+CI; subsumes D-A and D-J |
| D-A | `block-stale-skill-version.sh` reads MAIN's index | CRITICAL | DA | Fixed by documenting + mitigating — hook no-op for WT commits; subshell-`cd`; OOS follow-up to fix the hook |
| D-B | `/run-plan auto` refresh creates 2nd WT | CRITICAL | DA | Fixed — Phase 2 edits `/run-plan` to emit `parent=run-plan`; Phase 0 adds `.zskills-tracked` SKIP; AC9 + smoke #4 verify |
| D-C | `branch_prefix` hardcoded | MAJOR | DA | Fixed — Phase 0 reads `execution.branch_prefix`, defaults `feat/`; `--branch-name` uses `"${BRANCH_PREFIX}${TRACKING_ID}"`; Phase 3 asserts |
| D-D | rc=3 UX cliff | MAJOR | DA | Fixed — explicit "User-facing recovery prose" for rc=3 (delete-branch) and rc=10 (defer to script stderr) |
| D-E | Canary case 6 == case 1 | MAJOR | DA | Fixed — case 6 reworked to `ALREADY_MANAGED=1`; case 7 added (unrecognized parent → would-create); 10 distinct cases |
| D-F | Skill-tool dispatch indistinguishable | MINOR | DA | Justified — future-author note + `.zskills-tracked` SKIP catches common case; `parent=` is polite signal; CLAUDE_TEMPLATE.md follow-up |
| D-G | Dirty-worktree resume | MAJOR | DA | Fixed — staged-set defense `exit 1` emits recovery message pointing at `git status`; dirty subcase graceful-degrade |
| D-H | Modernization-from-MAIN loses input | MINOR | DA | Fixed — Phase 0 cp-seed on rc=0 when MAIN has prior plan but WT doesn't |
| D-I | `check_fixed --trailer` brittle | MINOR | DA | Fixed — same as R-F10 |
| D-J | Bump-dance cross-tree content hash | MINOR | DA | Fixed — subsumed by R-F12/D-A |
| D-K | Smoke-test accumulation | MINOR | DA | Fixed — smoke #1 uses `SMOKE_TEST_$(date +%s)`; cleanup removes WT + branch with error visibility |

**Totals (round 2):** 23 addressed (20 Fixed, 3 Justified — R-F7
sample-pass, R-F8 LLM-behavioral, D-F defense-in-depth). 4 CRITICALs
fixed. R1 regressions re-fixed in v3: R2, R5, R8, D3, D8.

---

## Round 3 Disposition

R3: 8 reviewer + 5 DA; 1 CRITICAL (DA F1 multi-fence) fixed.

| # | Finding | Sev | Src | Disposition |
|---|---------|-----|-----|-------------|
| R3-R-F1 | State-file never cleaned up | MAJOR | R | Fixed — Phase 6 step 4 appends `rm -f "$STATE_FILE"`; lifecycle paragraph in D&C |
| R3-R-F2 | Concurrent-slug race undocumented | MAJOR | R | Fixed — D&C "Concurrent-slug race" paragraph: same-slug unsupported, different slugs supported, `--allow-resume` handles WT race |
| R3-R-F3 | Prose-vs-bash mismatch on delegation gate | MINOR | R | Fixed — SKIP cond #3 prose reworded to "known-name allowlist"; matches bash + canary case 7 |
| R3-R-F4 | R2 D-B disposition cites wrong line numbers | MINOR | R | Fixed — updated to structural anchor ("Check for staleness"), line range advisory only |
| R3-R-F5 | metadata.version regex doesn't enforce "today" | MINOR | R | Justified — bump dance uses `date +%Y.%m.%d`; CI's `skill-version-stage-check.sh` is the freshness backstop |
| R3-R-F6 | Canary doesn't exercise parser strip | MINOR | R | Justified — strip is LLM-behavioral; bracketed by Phase 3 keyword scan + canary case 7 (same as R2 R-F8) |
| R3-R-F7 | Plan length growth | MINOR | R | Justified — positive growth audit; every line closes a specific finding |
| R3-R-F8 | `derive_output_paths` empty-OUTPUT_FILE_REL edge case | MINOR | R | Fixed — explicit `if [ -z "$OUTPUT_FILE_REL" ]` empty-check with clear error |
| R3-D-F1 | Phase 0 multi-fence collapses cross-fence vars + `derive_output_paths` fn | CRITICAL | DA | Fixed — CRITICAL implementer note at top of Phase 1: all Phase 0 chunks MUST merge into a SINGLE `` ```bash `` block in final SKILL.md. Phase 3 fence-count assertion enforces `PHASE_0_BLOCK_COUNT=1`. Distinguishes within-phase fence-merge from cross-phase state-file persistence |
| R3-D-F2 | Step 4 report doesn't differentiate auto-created vs pre-existing WT | MINOR | DA | Fixed — 2-branch template: `Worktree (auto-created): ...` + cleanup cmd vs `Worktree (pre-existing): ...`. New AC added |
| R3-D-F3 | `.zskills-tracked` in MAIN silently disables auto-worktree | MINOR | DA | Fixed — SKIP tightened to `[ "$TOPLEVEL" != "$MAIN_ROOT" ]`; trust-model paragraph + Phase 3 keyword assert + canary trust-model note |
| R3-D-F4 | Concurrent same-slug clobbers state file + WT | MINOR | DA | Justified — same fix surface as R3-R-F2; staged-set defense surfaces error if race fires; flock/PID-suffix is real complexity for out-of-scope concurrency |
| R3-D-F5 | `derive_output_paths` refuses legit abs paths inside MAIN | MINOR | DA | Fixed — REMAP arm added: `$MAIN_ROOT/X` → `$WT_PATH/X` with stderr breadcrumb; only paths outside both refused |

**Totals (round 3):** 13 addressed (9 Fixed, 4 Justified). CRITICAL
(D-F1) fixed.

**Justified re-audit:** R9, R11, R-F7, R-F8, D-F still hold under R3
evidence. No prior Justified item flipped.
