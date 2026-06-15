# /draft-tests — Phase 6 (tests, conformance, mirror, auto-land)

Phase 6 of `/draft-tests`. The orchestrator dispatches here after
Phase 1-4 ([modes/draft.md](draft.md)) and Phase 5
([modes/backfill.md](backfill.md)) have written the plan changes.

This is the final phase: re-verify Completed-phase checksums (via the
Phase 5 verify-script — repeated here as a final gate per AC-5.9),
ensure the skill's own test coverage is green, re-mirror the skill into
`.claude/skills/`, auto-commit the plan file when in a worktree, and
(when `$AUTO_FLAG=1`) dispatch `/land-pr` to ship the augmented plan
through CI to main.

Variables from prior phases still in scope: `$PLAN_FILE`,
`$TRACKING_ID`, `$PIPELINE_ID`, `$AUTO_FLAG`, `$MAIN_ROOT`, `$TOPLEVEL`,
`$WT_PATH`.

## Phase 6 — Tests, conformance, worked example, mirror

This is the final phase. After all Phase 1–5 work has been written,
the implementing agent: (1) ensures the skill's own test coverage is
green, (2) ships the worked-example fixtures, (3) re-mirrors the
source skill into `.claude/skills/`, and (4) writes the **finalize
tracking marker** and flips the fulfillment marker to
`status: complete`. Mirrors `/draft-plan` Phase 6's post-finalize
contract.

### Test coverage

The skill's tests live under `tests/`, split per implementation phase
to keep individual files readable: `tests/test-draft-tests.sh`
(Phase 1) plus `tests/test-draft-tests-phase{2,3,4,5}.sh`. Each is
registered in `tests/run-all.sh` alongside the other skill-conformance
peers (e.g., `test-skill-conformance.sh`, `test-skill-invariants.sh`,
`test-mirror-skill.sh`). Per-skill conformance assertions live in
`tests/test-skill-conformance.sh` in a dedicated `draft-tests` block;
the block carries a tag-line comment referencing WI 6.3 of
`plans/DRAFT_TESTS_SKILL_PLAN.md` as the authoritative enumeration
source so future WI 6.3 additions drive a single edit (a new
conformance line) rather than coupled edits at WI 6.3 + AC-6.2
literal.

### Worked example

The repo ships a small, purpose-built before/after example pair under
`tests/fixtures/draft-tests/examples/` (NOT `plans/examples/`) — a
README explains the directory's purpose, plus the
`DRAFT_TESTS_EXAMPLE_PLAN_before.md` and
`DRAFT_TESTS_EXAMPLE_PLAN.md` files. The diff between them shows what
a hypothetical `/draft-tests` invocation produces: AC-ID prefixes
assigned to a Pending phase's bullets, plus an appended `### Tests`
subsection in that Pending phase. The Completed phase is
byte-identical between the two files. The example files are pure
documentation — they are NOT invoked by `tests/run-all.sh` and NOT
wired into `/run-plan`. Fixtures and worked examples co-locate under
`tests/fixtures/` to keep them out of any future `plans/` glob.

### Mirror

After every phase's source-skill edits land, re-mirror the skill via
the canonical helper:

```bash
bash scripts/mirror-skill.sh draft-tests
```

The helper handles per-file copy, orphan detection (per-file `rm`,
not `rm -rf` — hook-compatible), and post-regen `diff -rq`
verification. Inline `cp` / `rm -rf` is forbidden — see
`feedback_claude_skills_permissions.md`. **Never edit any file under
`.claude/skills/draft-tests/` directly during development.** All
edits go to `skills/draft-tests/` first.

### Auto-commit the plan file (if in a worktree)

After mirroring, when `$TOPLEVEL` is a worktree (not main), stage and
commit `$PLAN_FILE` so the drafted test specs are captured on the
feature branch rather than left dirty in main. This pairs with the
preamble's structural isolation:

```bash
# Self-contained; belt-and-suspenders cd in case WT_PATH was set above.
[ -n "${WT_PATH:-}" ] && cd "$WT_PATH" 2>/dev/null || true
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
TOPLEVEL=$(git rev-parse --show-toplevel)
if [ "$TOPLEVEL" != "$MAIN_ROOT" ]; then
  # Re-source path-config under the worktree root so $ZSKILLS_PLANS_DIR
  # etc resolve to TOPLEVEL/... rather than $CLAUDE_PROJECT_DIR/... — R3-1.
  # Belt-and-suspenders: the preamble already exported this, but the
  # fence re-exports in case the preamble code path was bypassed
  # (e.g., caller-in-worktree, where WT_PATH was empty but TOPLEVEL is
  # already a worktree — we want paths anchored on TOPLEVEL).
  export ZSKILLS_PATHS_ROOT="$TOPLEVEL"
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-paths.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-paths.sh"
  fi

  # R3-1 path-remap: if $PLAN_FILE was computed BEFORE the preamble set
  # $ZSKILLS_PATHS_ROOT (e.g., a stale value cached in the caller's
  # argument-resolution block), it may still be MAIN-anchored. Re-anchor
  # to TOPLEVEL. This is the load-bearing remap.
  case "$PLAN_FILE" in
    "$MAIN_ROOT"/*) PLAN_FILE="$TOPLEVEL/${PLAN_FILE#"$MAIN_ROOT/"}" ;;
  esac

  # Portable FILE_REL (DA-R2-1, R3-6: adapted from warn-config-drift.sh:181-203).
  FILE_REL=""
  if FILE_REL=$(realpath --relative-to="$TOPLEVEL" "$PLAN_FILE" 2>/dev/null) \
       && [ -n "$FILE_REL" ]; then
    case "$FILE_REL" in /*) FILE_REL="" ;; esac
  fi
  if [ -z "$FILE_REL" ]; then
    ABS_FILE=$(cd "$(dirname "$PLAN_FILE")" 2>/dev/null && pwd)/$(basename "$PLAN_FILE")
    case "$ABS_FILE" in
      "$TOPLEVEL"/*) FILE_REL="${ABS_FILE#"$TOPLEVEL"/}" ;;
      *) echo "draft-tests: cannot normalize $PLAN_FILE vs $TOPLEVEL" >&2; exit 1 ;;
    esac
  fi
  # Out-of-tree guard (DA-R2-5). After the path-remap above, FILE_REL
  # should never be `../*` for legitimate inputs; if it is, fail loud
  # (something is wrong with the caller's resolution).
  case "$FILE_REL" in
    /*|../*) echo "draft-tests: $PLAN_FILE is outside worktree $TOPLEVEL" >&2; exit 1 ;;
  esac

  git -C "$TOPLEVEL" add "$FILE_REL"
  STAGED=$(git -C "$TOPLEVEL" diff --cached --name-only)
  if [ "$STAGED" != "$FILE_REL" ]; then
    echo "draft-tests: unexpected staged set: $STAGED (expected $FILE_REL only)" >&2
    exit 1
  fi
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi

  # Per-skill commit subject (R2-F8: case-stmt, not table cell).
  BASE=$(basename "$FILE_REL" .md)
  case "draft-tests" in
    draft-plan)  COMMIT_MSG_SUBJECT="docs(plans): draft $BASE" ;;
    refine-plan) COMMIT_MSG_SUBJECT="docs(plans): refine $BASE" ;;
    draft-tests) COMMIT_MSG_SUBJECT="docs(tests): draft test specs for $BASE" ;;
  esac

  if [ -n "$COMMIT_CO_AUTHOR" ]; then
    git -C "$TOPLEVEL" commit --trailer "Co-Authored-By: $COMMIT_CO_AUTHOR" -m "$COMMIT_MSG_SUBJECT"
  else
    git -C "$TOPLEVEL" commit -m "$COMMIT_MSG_SUBJECT"
  fi
fi
```

### Auto-land via /land-pr (when `auto` was passed)

Issue #581: in projects with `execution.landing: pr` +
`main_protected: true`, the plan with appended test specs is committed
in the worktree (above) but never reaches main without a `/land-pr`
dispatch. When the user passed the `auto` positional token, dispatch
`/land-pr` so the branch pushes, a PR opens, CI runs, and auto-merge
lands the test-spec-augmented plan on main. Without `auto`, the
worktree commit stands and the caller lands manually.

```bash
if [ -n "${ZSH_VERSION:-}" ]; then setopt KSH_ARRAYS BASH_REMATCH SH_WORD_SPLIT 2>/dev/null || true; fi
if [ "${AUTO_FLAG:-0}" = "1" ] && [ "$TOPLEVEL" != "$MAIN_ROOT" ]; then
  if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
    export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
  else
    . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
  fi
  BRANCH_NAME=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)
  SLUG="$TRACKING_ID"
  PR_TITLE="docs(tests): draft test specs for $(basename "$PLAN_FILE" .md) via /draft-tests"
  BODY_FILE="/tmp/pr-body-draft-tests-${SLUG}-$$.md"
  RESULT_FILE="/tmp/land-pr-result-draft-tests-${SLUG}-$$.txt"
  cat > "$BODY_FILE" <<BODY
## Summary

\`/draft-tests\` appended \`### Tests\` subsections to Pending phases of
\`$PLAN_FILE\` via adversarial review (senior-QE reviewer +
devil's-advocate + refiner). Completed phases were NOT modified
(checksum-gated).

## Test plan

- [x] Test-spec-augmented plan committed on the draft-tests branch
      (worktree-isolated)
- [x] Completed-phase byte-identity verified via Phase-1 checksums
- [ ] No functional tests — this PR ships test SPECS in a plan document;
      CI will run skill-conformance / hook / fixture suites
BODY
  LAND_ARGS="--branch=$BRANCH_NAME --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=draft-tests --worktree-path=$TOPLEVEL --tracking-id=draft-tests.$SLUG --auto"

  # Skill: { skill: "land-pr", args: "$LAND_ARGS" }

  # Allow-list parse the /land-pr result (canonical caller-loop pattern —
  # never `source`). See skills/land-pr/references/caller-loop-pattern.md.
  if [ -f "$RESULT_FILE" ]; then
    # zsh portability (#1155): assoc subscripts must be UNQUOTED — zsh uses the
    # subscript text verbatim, so LP["$KEY"] and ${LP[STATUS]} address different
    # keys. Keep assignment and lookup styles consistent-unquoted.
    declare -A LP
    while IFS='=' read -r KEY VALUE; do
      case "$KEY" in
        STATUS|PR_URL|PR_NUMBER|CI_STATUS|PR_STATE|REASON)
          LP[$KEY]="$VALUE" ;;
        "") ;;
        *) ;;  # unknown keys ignored (forward-compat)
      esac
    done < "$RESULT_FILE"
    echo "/land-pr: STATUS=${LP[STATUS]:-?} CI_STATUS=${LP[CI_STATUS]:-?} PR=${LP[PR_URL]:-none}" >&2
    rm -f "$RESULT_FILE"
  else
    echo "WARN: /draft-tests: /land-pr produced no result file at $RESULT_FILE" >&2
  fi
fi
```

### Finalize tracking marker

After the mirror succeeds, write the `finalize` step marker and
update the fulfillment marker to `status: complete`. Mirrors
`/draft-plan`'s Phase 6 post-finalize contract:

```bash
if [ -f "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh" ]; then
  export CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
  . "${CLAUDE_PLUGIN_ROOT}/skills/update-zskills/scripts/zskills-resolve-config.sh"
else
  . "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-resolve-config.sh"
fi
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-draft-tests.$TRACKING_ID}"
[ -n "$PIPELINE_ID" ] || { echo "tracking: empty PIPELINE_ID — refusing flat write" >&2; exit 1; }
printf 'completed: %s\n' "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/step.draft-tests.$TRACKING_ID.finalize"

printf 'skill: draft-tests\nid: %s\nplan: %s\nstatus: complete\ndate: %s\n' \
  "$TRACKING_ID" "$PLAN_FILE" "$(TZ="${TIMEZONE:-UTC}" date -Iseconds)" \
  > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.draft-tests.$TRACKING_ID"
```

The finalize marker basename is the canonical
`step.draft-tests.$TRACKING_ID.finalize` per the tracking-marker
scheme (see `docs/tracking/TRACKING_NAMING.md`). The fulfillment
marker is the same one created in Phase 1 — only the file's `status:`
line changes from `started` to `complete`. The plan file itself has
already been written by Phases 3–5; this step records skill
completion, not plan content.
