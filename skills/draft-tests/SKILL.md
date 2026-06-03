---
name: draft-tests
disable-model-invocation: false
argument-hint: "<plan-file> [rounds N] [auto] [<guidance>]"
description: >-
  Draft test specifications into an existing plan through iterative
  adversarial review. Appends a `### Tests` subsection per pending phase
  via a senior-QE reviewer + devil's-advocate + refiner loop. Completed
  phases are never modified (checksum-gated). Sister skill to /draft-plan,
  scoped to test specs.
metadata:
  version: "2026.06.03+a3e088"
---

# /draft-tests \<plan-file> [rounds N] [<guidance>] — Adversarial Test-Spec Drafter

Sister skill to `/draft-plan`: same drafting + adversarial-review
machinery, scoped to test specifications. Given the path to an existing
plan (the kind `/draft-plan` produces), this skill appends a
`### Tests` subsection into every pending phase, then runs a senior-QE
review loop (reviewer + devil's advocate + refiner) until the specs hold
up.

The reader of the appended specs is the AI implementing agent that
`/run-plan` dispatches — not a human — so specs ride along inside the
phases `/run-plan` already executes. No companion document. No
`/run-plan` loader patch.

**Completed phases are never mutated.** Checksum-gated, per
`/refine-plan`'s immutability pattern. `/draft-tests` ALSO preserves
every trailing non-phase section byte-identical at the file-write level
— a stricter invariant than `/refine-plan`. Test gaps in completed
phases are surfaced by appending a new top-level
`## Phase N — Backfill tests for completed phases X–Y` BEFORE any
existing trailing sections.

**Ultrathink throughout.**

## Preflight — top-level dispatch required

This skill internally dispatches reviewer + devil's-advocate + refiner sub-agents in parallel. It MUST run in a context that has the `Agent` (or `Task`) tool available.

Before doing any other work, verify your tool list contains `Agent` or `Task`. If neither is present, STOP and report:

> ERROR: /draft-tests requires top-level Agent dispatch capability. This invocation is running as a subagent (no Agent tool — verified by inspecting your tool list). Subagents cannot dispatch sub-subagents (Anthropic design — https://code.claude.com/docs/en/sub-agents).
>
> Re-invoke as one of:
>   - User slash command: `/draft-tests <plan-file>`
>   - Top-level `Skill` tool: `Skill(skill="draft-tests", args="<plan-file>")`
>   - Inline orchestration by a top-level Claude that has `Agent`
>
> Do NOT continue. Single-agent inline degradation produces rubber-stamp findings without the adversarial diversity this skill's value depends on. The CLAUDE.md memory anchor `feedback_multi_agent_skills_top_level.md` is the recurring failure mode this preflight catches.

Do not proceed past this preflight without `Agent` access.

## Worktree preamble — ensure isolation when main is protected

Before parsing arguments, ensure a worktree exists when main is protected.
Dispatch the canonical helper; if `main_protected: true` and the caller is
in main, the helper creates a worktree and prints its path on stdout
(empty string when no worktree is required). When non-empty, `cd` into it
and export `ZSKILLS_PATHS_ROOT` so downstream path-resolution anchors on
the worktree, not main:

```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TOPLEVEL=$(git rev-parse --show-toplevel)
HELPER="$ZSKILLS_SKILLS_ROOT/create-worktree/scripts/ensure-worktree.sh"
# Caller-side install-integrity fallback (DA-R3-2): if /update-zskills
# Step 3 ran as per-file-diff and skipped the new file, the helper itself
# is missing. Emit an actionable exit-11 message instead of bash's
# `No such file or directory`.
if [ ! -x "$HELPER" ]; then
  echo "draft-tests: ensure-worktree.sh missing at $HELPER — run /update-zskills to repair" >&2
  exit 11
fi
# Resolve $PLAN_FILE and derive $TRACKING_ID before the worktree preamble
# so the helper's --pipeline-id / positional slug are non-empty. Mirrors
# the Arguments-section detection rule: first $ARGUMENTS token ending in
# `.md` or containing `/` is the plan file; resolve bare names via
# $ZSKILLS_PLANS_DIR. Phase 1's Tracking-fulfillment fence re-derives
# $TRACKING_ID idempotently from the same $PLAN_FILE.
if [ -z "${PLAN_FILE:-}" ]; then
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi
  for tok in $ARGUMENTS; do
    case "$tok" in
      */*) PLAN_FILE="$tok"; break ;;
      *.md) PLAN_FILE="$ZSKILLS_PLANS_DIR/$tok"; break ;;
    esac
  done
fi
if [ -z "${PLAN_FILE:-}" ]; then
  echo "draft-tests: PLAN_FILE not resolved from \$ARGUMENTS (need a *.md token)" >&2
  exit 2
fi
TRACKING_ID=$(basename "$PLAN_FILE" .md | tr '[:upper:]' '[:lower:]' | tr '_' '-')
WT_PATH=$(bash "$HELPER" \
  --prefix drafttests \
  --pipeline-id "draft-tests.${TRACKING_ID}" \
  --allow-resume \
  --purpose "draft-tests auto-worktree; isolate test-spec drafting from main" \
  "${TRACKING_ID}")
RC=$?
if [ "$RC" -ne 0 ]; then
  echo "ensure-worktree failed (rc=$RC) for /draft-tests" >&2
  # rc=3 (poisoned branch): suggest `/create-worktree resume <slug>` or
  # delete the poisoned branch. rc=11: helper install-integrity — run
  # `/update-zskills` to repair. Other codes: see helper script header.
  exit "$RC"
fi
if [ -n "$WT_PATH" ]; then
  cd "$WT_PATH" || { echo "draft-tests: cd $WT_PATH failed" >&2; exit 1; }
  # R3-1 path-resolution fix: re-anchor zskills-paths.sh under the
  # worktree so subsequent $ZSKILLS_PLANS_DIR / $ZSKILLS_AUDIT_DIR /
  # $ZSKILLS_ISSUES_DIR resolutions land in WT, not main. Export (not
  # just set) so child shells / re-sourcing inherits it.
  export ZSKILLS_PATHS_ROOT="$WT_PATH"
fi
# Empty $WT_PATH means no worktree was created (caller already in one OR
# main not protected); proceed in cwd. $ZSKILLS_PATHS_ROOT stays unset
# in that case, so paths fall back to $CLAUDE_PROJECT_DIR as before.
```

## Arguments

```
/draft-tests <plan-file> [rounds N] [auto] [guidance...]
```

- **plan-file** (required) — path to the plan `.md` file. If the token
  contains `/`, use as-is; otherwise resolve via
  `$ZSKILLS_PLANS_DIR/<token>` (sourcing
  `.claude/skills/update-zskills/scripts/zskills-paths.sh` from the
  orchestrator's bash fence; falls back to `plans/` when config silent).
- **rounds N** (optional) — max review/refine cycles. Default: 3 (matches
  `/draft-plan`; `/refine-plan`'s default is 2 because it operates on an
  already-refined plan, while `/draft-tests` is typically blank-slate
  spec drafting).
- **auto** (optional positional token) — after the worktree auto-commit
  in Phase 6 succeeds, dispatch `/land-pr` to push the branch, open a
  PR, monitor CI, and auto-merge. Without `auto`, the spec-augmented
  plan is committed in the worktree but no PR is opened. Mirrors `auto`
  in `/run-plan`, `/do`, `/fix-issues`, `/quickfix`, `/draft-plan`,
  `/refine-plan`.
- **guidance...** (optional) — any tokens not matched as plan file,
  `rounds N`, or `auto` are joined with spaces into **guidance text** —
  prepended to BOTH the reviewer and devil's-advocate prompts in Phase 4
  as a "User-driven scope/focus directive" section, mirroring
  `/refine-plan`'s positional-tail semantics. Empty guidance preserves
  byte-identical reviewer/DA prompt output (regression-safe). Guidance
  is **priming context** that shapes WHAT the agents pressure-test —
  NOT factual claims they should act on without verification.
  Verify-before-fix discipline still applies in the refiner.

**Detection:** scan `$ARGUMENTS` from the start:
- The **first** token ending in `.md` OR containing `/` is the plan
  file. If the token contains `/`, use as-is; otherwise resolve via
  `$ZSKILLS_PLANS_DIR/<token>` (falls back to `plans/` when config silent).
- `rounds` followed by a numeric argument sets max cycles. (`rounds`
  not followed by a number is treated as guidance text, not the
  keyword.)
- `auto` (whitespace-anchored, case-insensitive) sets `AUTO_FLAG=1` for
  the Phase 6 `/land-pr` dispatch. The token is consumed by the flag
  parse and does NOT enter guidance text.
- Any tokens not matched as the plan file, `rounds N` keyword, or the
  `auto` token are joined with spaces into guidance text.
- If no plan file is detected, **error:**
  `Usage: /draft-tests <plan-file> [rounds N] [auto] [guidance...]`

```bash
AUTO_FLAG=0
if [[ "$ARGUMENTS" =~ (^|[[:space:]])[aA][uU][tT][oO]($|[[:space:]]) ]]; then
  AUTO_FLAG=1
fi
```

Examples:
- `/draft-tests plans/FEATURE.md`
- `/draft-tests plans/FEATURE.md rounds 4`
- `/draft-tests FEATURE.md` → reads `$ZSKILLS_PLANS_DIR/FEATURE.md`
- `/draft-tests plans/FOO.md focus on integration tests`
- `/draft-tests plans/FOO.md rounds 3 emphasize property-based coverage`

## Execution path

After the preflight, worktree preamble, and argument parsing above are
complete, select the execution path based on what the invocation needs
to do. **Read each listed mode/reference file in full and follow its
procedure end-to-end. Do not proceed past this router without reading
the files for your path.**

The standard fresh invocation runs the entire pipeline in order: draft →
backfill (if needed) → land. Mode files are listed in the order they
execute; references are loaded on demand by the mode files.

| Phase / concern | File |
|---|---|
| Phases 1-4 (parse, language detect, draft, adversarial review) | [modes/draft.md](modes/draft.md) |
| Phase 5 (backfill mechanics + re-invocation) | [modes/backfill.md](modes/backfill.md) |
| Phase 6 (tests, conformance, mirror, auto-land via /land-pr) | [modes/land.md](modes/land.md) |
| `## Design & Constraints` (cross-phase invariants for Phases 1-4) | [references/design-constraints.md](references/design-constraints.md) |
| Test spec vocabulary, Key Rules, Edge Cases | [references/test-spec-format.md](references/test-spec-format.md) |

**Routing rules:**

- **Fresh invocation** (no `### Tests` subsections in the plan yet):
  load `modes/draft.md` first; `modes/draft.md` itself calls into
  `modes/backfill.md` when Phase 5's gap detection requires a backfill
  phase, then proceeds to `modes/land.md`.
- **Re-invocation against a plan that already has `### Tests`
  subsections** (refinement mode, per Phase 5 WI 5.5): still start with
  `modes/draft.md` for Phase 1 parsing + Phase 2 detection; the
  re-invocation detector in `modes/backfill.md` short-circuits Phase 3
  and runs the Phase 4 review loop directly against the existing specs.
- **Backfill of completed phases without any pending phases**: still
  load `modes/draft.md` (Phases 1-2 always run); Phase 4 may run with
  the empty draft if there are no pending non-delegate phases, but
  `modes/backfill.md` will append a new backfill phase and re-enter the
  Phase 4 review loop with that phase as Pending.

`references/design-constraints.md` and `references/test-spec-format.md`
are cited from the mode files where their content applies; the agent
should read them when the mode prose points at them.

## Key Rules

See [references/test-spec-format.md](references/test-spec-format.md) —
the Key Rules and Edge Cases sections live there alongside the test
spec format vocabulary they reference.
