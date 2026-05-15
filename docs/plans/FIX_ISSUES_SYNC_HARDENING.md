---
issue: 231
title: /fix-issues sync — bootstrap empty issues_dir (#231)
created: 2026-05-12
status: active
---

# Plan: /fix-issues sync — bootstrap empty issues_dir (#231)

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

`/fix-issues sync` has a correctness gap that this plan closes:

- **#231 — bootstrap gap.** When `$ZSKILLS_ISSUES_DIR/` has no tracker files (no `*_ISSUES.md`, no `ISSUES_PLAN.md`), `skills/fix-issues/SKILL.md:521,542` does `ls ... 2>/dev/null` and silently returns empty. The research-and-record loop has nothing to write into and silently no-ops; the sync summary reports `K=0 trackers updated` without flagging the gap.

The sibling `#233 — main_protected` violation was closed by `docs/plans/PREAMBLE_WORKTREE_GATE.md` Phase 4 (merged in commit `c1b0962`), which inserted an unconditional `ensure-worktree.sh` preamble at the top of `## Sync` and rewrote the step-5 commit to land on the worktree's feature branch. The residual gap PREAMBLE didn't cover is the `/land-pr` dispatch + tracking marker — Phase 3 of this plan adds that on top of PREAMBLE's commit.

## Dependencies

This plan depends on `docs/plans/PREAMBLE_WORKTREE_GATE.md` Phase 4 (status: complete; merged in commit c1b0962). PREAMBLE Phase 4 inserted the `ensure-worktree.sh` preamble at the top of `## Sync` in `skills/fix-issues/SKILL.md` and rewrote the step-5 commit to scope to `SPRINT_REPORT.md`. THIS plan adds the residual `/land-pr` dispatch + tracking marker on top of that work. The bootstrap (#231) is independent of PREAMBLE — it would land cleanly even if PREAMBLE had not.

## Acceptance Criteria (plan-level)

- [ ] AC-P.1 — `/fix-issues sync` on a repo with empty `$ZSKILLS_ISSUES_DIR/` and at least one open GH issue bootstraps a tracker file, populates it with the open issues, and runs the research-agent dispatch on those entries. The `K=0 trackers updated` silent-no-op from #231 is no longer reachable.
- [ ] AC-P.3 — When the `/land-pr` dispatch added in Phase 3 is taken, `gh issue close` calls in Sync step 4 are deferred until AFTER `/land-pr` returns a success status (`created`, `monitored`, or `merged`). If `/land-pr` fails, no GitHub issues are closed (no state divergence).
- [ ] AC-P.6 — Both Standalone Sync (post-PREAMBLE `## Sync`) and Phase 1a Sync (`skills/fix-issues/SKILL.md:507-565`) bootstrap consistently. Sprint-mode auto-sync re-entry (`skills/fix-issues/SKILL.md:685-693`) also benefits from the bootstrap fix because it re-enters standalone sync.
- [ ] AC-P.7 — `skills/fix-issues/SKILL.md` carries a current `metadata.version` after every commit (per-phase commits each bump; the final value is the hash of the final tree). `diff -rq skills/fix-issues .claude/skills/fix-issues` empty.
- [ ] AC-P.8 — `bash tests/run-all.sh` exits 0. `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-P.9a — The plan-landing PR body does NOT contain a GitHub auto-close directive against #231 (verb forms `close[sd]?`, `fixe[sd]?`, `resolve[sd]?` followed by `#231`). Verification (case-insensitive, no `^` anchor, captures bulleted/inline forms): `gh pr view <plan-PR> --json body --jq '.body' | grep -ciE '\(close[sd]?\|fixe[sd]?\|resolve[sd]?\) #231\b'` returns 0.
- [ ] AC-P.9b — The plan-landing branch's commit messages also do NOT contain a GitHub auto-close directive against #231. GitHub auto-closes from commit messages on squash-merge regardless of negation/quoting. Verification: `git log --format=%B origin/main..HEAD | grep -ciE '\(close[sd]?\|fixe[sd]?\|resolve[sd]?\) #231\b'` returns 0 on the plan-landing branch.
- [ ] AC-P.9d — Runtime sync PRs (those produced by `/fix-issues sync` after this plan lands) do NOT include an auto-close directive for issues that step 4b already closed via the GitHub API — avoids redundant API calls at merge.
- [ ] AC-P.12 — Sync's `/land-pr` dispatch does NOT pass `--auto`. Verification (sync-section scoped): `awk '/^## Sync /,/^## /' skills/fix-issues/SKILL.md | grep -cE -- '--auto'` returns 0 (sync is human-review-only; merge happens manually after the user inspects the PR). Scoping to `## Sync` is intentional: an older Phase-6 sprint-mode paragraph documents `gh pr merge --auto --squash` for an unrelated code path; a whole-file regex would falsely trip on that working prose.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Worktree setup + plan scaffold | ✅ | (bookkeeping) | Branch + frontmatter + plan parses |
| 2 — Bootstrap detector for empty issues_dir | ✅ | `f6964c1` | Bootstrap subroutine + row-writer + version bump; 3023/3023 tests pass |
| 3 — `/land-pr` dispatch + tracking marker | ✅ | `37f7af4` | /land-pr dispatch + tracking marker; AC-3.2/P.12 grep scoped to ## Sync (over-broad whole-file regex corrected) |
| 4 — Edge cases | ⬚ | | Hardening |
| 5 — Final version verification, conformance, run-all | ⬚ | | Verify (or rebump on verifier polish) + full test pass |

## Design & Constraints (plan-wide)

### Bootstrap filename — `ISSUES_PLAN.md`

Bootstrap creates `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md`, the historical canonical name. Sync's own glob (`skills/fix-issues/SKILL.md:519-525, 542`) explicitly accepts `*ISSUES*.md` OR the literal `ISSUES_PLAN.md`; path-migration script (`skills/update-zskills/scripts/migrate-paths.sh:613`) lists it first in its canonical filenames array; skill description (`skills/fix-issues/SKILL.md:31`) already names it. The dashboard does NOT scan `issues_dir` (`skills/zskills-dashboard/scripts/zskills_monitor/collect.py` only walks `plans_dir` at lines 1143-1147, 1249-1251), so tracker filename has no dashboard effect.

Bootstrap header template (written ONCE; subsequent sync runs read the existing file):

```markdown
---
title: Issues — Auto-Bootstrapped Tracker
status: active
created: YYYY-MM-DD
---

# Issues — Auto-Bootstrapped Tracker

Created by `/fix-issues sync` on YYYY-MM-DD because this repo had no tracker files in `$ZSKILLS_ISSUES_DIR/` when sync ran. Split into domain-specific `*_ISSUES.md` files as patterns emerge — sync's glob picks them all up.

## Open Issues

(rows added by sync step 5; one row per open GH issue not yet researched)
```

Date in `America/New_York` per `.claude/zskills-config.json:timezone`.

Row format added by sync's step-5 row-writer (one per open GH issue not yet in any tracker):

```markdown
### #NNN — <issue title>

**Labels:** <comma-separated labels from `gh issue view`>
**Verdict:** NOT YET RESEARCHED

(research blurb added by step-6 research-agent dispatch)
```

This template makes the no-blurb case visible (`grep -B1 'NOT YET RESEARCHED'` lists every issue still awaiting research).

### `/land-pr` dispatch — caller-list note

`/fix-issues sync` is NOT a new conformance-locked `/land-pr` caller. The conformance fingerprint at `tests/test-skill-conformance.sh:519-538` lists five files (`skills/run-plan/modes/pr.md`, `skills/commit/modes/pr.md`, `skills/do/modes/pr.md`, `skills/fix-issues/modes/pr.md`, `skills/quickfix/SKILL.md`) and asserts each contains the substring `land-pr`. The new sync dispatch lives in `skills/fix-issues/SKILL.md` — a different file — and adds a `land-pr` reference there, which neither breaks the substring check on the five tracked files nor adds a new entry to the tracked list.

### Sync uses canonical monitor flow, but NO fix-cycle agent dispatch

Sync passes neither `--auto` nor `--no-monitor`. The canonical monitor flow runs so CI failures surface proactively at PR creation time, matching the 4 no-auto canonical callers (`/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`). What sync strips is the **fix-cycle agent dispatch** on `CI_STATUS=fail`: the canonical agent (`skills/land-pr/references/fix-cycle-agent-prompt-template.md`) is specced for code+test PRs (read CI log → diagnose → patch → commit). On a tracker-content PR, the agent has no legitimate fix to apply — a lint warning, a stale snapshot diff, or a flaky workflow would tempt it to mutate tracker entries, edit test workflows, or hallucinate fixes against lint warnings.

Sync is the first canonical-caller variant to skip fix-cycle entirely. The other 5 callers all default to `CI_MAX_ATTEMPTS=2` (verified at `skills/quickfix/SKILL.md:1076`). Precedent absence is acknowledged, not papered over; the principled justification (content-only PR, code-fix agent is hazardous) stands on its own.

### Skill versioning workflow (per phase)

Each phase that edits `skills/fix-issues/SKILL.md` ends with its own version bump and commit. The PreToolUse hook `block-stale-skill-version.sh` enforces this at every commit. Phase 5 handles the verifier-polish rebump case: if a Phase-4 verifier subagent committed a polish patch after the per-phase bump, Phase 5 detects the hash mismatch and emits a single rebump-commit on top:

```bash
HASH_NOW=$(bash scripts/skill-content-hash.sh skills/fix-issues)
VER_NOW=$(bash scripts/frontmatter-get.sh skills/fix-issues/SKILL.md metadata.version | sed 's/.*+//')
if [ "$HASH_NOW" != "$VER_NOW" ]; then
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$TODAY+$HASH_NOW"
  bash scripts/mirror-skill.sh fix-issues
  git add skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
  git commit -m "polish: rebump skills/fix-issues metadata.version to current content hash"
fi
```

### Bootstrap fires regardless of caller — Phase 1a is shared

The bootstrap subroutine lives in Phase 1a Sync. Phase 1a is shared between standalone sync (`/fix-issues sync` step 1 delegates to Phase 1a) and sprint mode (`/fix-issues N`). Both flows now trigger bootstrap when `issues_dir` is empty.

In sprint mode, the bootstrap file is written to the main repo working tree at Phase 1a (before sprint creates per-issue worktrees). Sprint's later cherry-pick / PR-mode phases pick it up via the same `git status --porcelain` enumeration this plan uses — bootstrap rides along with whatever the sprint commits. Under `main_protected: true` in sprint mode, sprint's per-issue worktree+PR model is already worktree-routed, so the bootstrap file lands as part of a per-issue PR.

### Hard constraints

- Do NOT call `gh pr create` or `gh pr merge --auto` directly. Dispatch `/land-pr`.
- Do NOT pass `--auto` to `/land-pr` from sync (AC-P.12). Sync is human-review-only.
- Do NOT pass `--no-monitor` to `/land-pr` from sync. Canonical monitor flow runs.
- Do NOT add `jq` to `skills/fix-issues/SKILL.md`. Use BASH_REMATCH / `grep -oE`.
- Do NOT bypass hooks with `--no-verify`.
- **Never write a literal GitHub auto-close directive (`Close[sd]? #N` / `Fixe[sd]? #N` / `Resolve[sd]? #N` against a real issue number) in any PR body, commit message, or plan prose unless that PR/commit IS the one that should close issue N at merge time.** GitHub auto-closes from BOTH PR body and commit message at squash-merge, regardless of negation, quoting, or backticks. Reference issues by bare `#231` when not closing. Past failures: PR #237 had the directive in the PR body; PR #243 had it in a commit message phrased as a negation. This plan itself uses bare `#231` throughout; AC-P.9a/b enforce this on the plan-landing PR.
- `metadata.version` bump on each `skills/fix-issues/SKILL.md` edit is mandatory.

### What this plan does NOT do

- Does not refactor sync's argument parsing or research-agent dispatch logic.
- Does not change sprint-mode (`/fix-issues N`) per-issue commit semantics.
- Does not add a `--auto` arg to sync.
- Does not dispatch a `/land-pr` fix-cycle agent on sync's PR (content-only; canonical agent is code+test-specced).

---

## Phase 1 — Worktree setup + plan scaffold

### Goal

Establish the feature branch worktree this plan runs in and ensure `/run-plan` can parse the plan file. Bookkeeping-only; no behavior changes to `skills/fix-issues/SKILL.md`.

### Work Items

- [ ] WI 1.1 — Confirm the worktree exists, the branch is the agreed feature branch, and it's pushed to `origin`.
- [ ] WI 1.2 — Confirm `docs/plans/FIX_ISSUES_SYNC_HARDENING.md` parses cleanly: frontmatter has `issue: 231`, `status: active`, Landing-mode blockquote is `PR`, phase headings use em-dash.
- [ ] WI 1.3 — Initial commit of the plan file on the feature branch (if not already committed).

### Design & Constraints

No `skills/fix-issues/SKILL.md` edits in this phase → no `metadata.version` bump.

### Acceptance Criteria

- [ ] AC-1.1 — `git rev-parse --abbrev-ref HEAD` returns the plan's feature branch name (not `main`/`master`).
- [ ] AC-1.2 — `head -10 docs/plans/FIX_ISSUES_SYNC_HARDENING.md | grep -E '^issue: 231'` returns a hit.
- [ ] AC-1.3 — `grep -nE '^## Phase [0-9]+ — ' docs/plans/FIX_ISSUES_SYNC_HARDENING.md` returns ≥5 phase headings with em-dash separator.
- [ ] AC-1.4 — `git log -1 --pretty=%s` includes the plan filename or a clear reference to it.

### Dependencies

None.

---

## Phase 2 — Bootstrap detector for empty `$ZSKILLS_ISSUES_DIR/`

### Goal

Address #231 — when sync scans `$ZSKILLS_ISSUES_DIR/` and finds zero tracker files, bootstrap an `ISSUES_PLAN.md` file with the header template specified in plan-wide Design & Constraints. Cover the shared Phase 1a code path.

### Work Items

- [ ] WI 2.1 — In `skills/fix-issues/SKILL.md` Phase 1a Sync, immediately before the gap-detection block at line 519-529, fetch the open-issue list AND count safely (single `gh` call, parsed for both count and number array). `grep -cE` over single-line JSON would return line-count not match-count — use `grep -oE | mapfile`:
  ```bash
  GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1) \
    || { echo "ERROR: 'gh issue list' failed:" >&2; echo "$GH_OUT" >&2; exit 1; }
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}
  ```
- [ ] WI 2.2 — Add the bootstrap subroutine before the existing `ls "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md ...` at line 521. **The heredoc body MUST be at column 0** when inserted into `skills/fix-issues/SKILL.md` — bash `<<TRACKER` (no `-` suffix) does not strip leading whitespace, and YAML frontmatter must start at column 0:
  ```bash
  mkdir -p "$ZSKILLS_ISSUES_DIR"
  EXISTING_TRACKERS=$(ls "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null | head -1)
  if [ -z "$EXISTING_TRACKERS" ]; then
    if [ "$OPEN_COUNT" -eq 0 ]; then
      echo "Sync complete. 0 open issues, no trackers needed."
      exit 0
    fi
    TODAY=$(TZ=America/New_York date +%Y-%m-%d)
    cat > "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" <<TRACKER
  ---
  title: Issues — Auto-Bootstrapped Tracker
  status: active
  created: $TODAY
  ---

  # Issues — Auto-Bootstrapped Tracker

  Created by \`/fix-issues sync\` on $TODAY because this repo had no tracker files in \`\$ZSKILLS_ISSUES_DIR/\` when sync ran.

  ## Open Issues

  (rows added by sync step 5 below)
  TRACKER
    echo "Bootstrapped $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
    BOOTSTRAP_NEW=yes
  else
    BOOTSTRAP_NEW=no
  fi
  ```
  (The heredoc body lines in this plan are shown indented for plan readability; in the SKILL.md insertion they must be at column 0.)
- [ ] WI 2.3 — Update the prose at `skills/fix-issues/SKILL.md:558-561` to add: "Empty `issues_dir` now triggers bootstrap; this failure mode is structurally prevented." (Prose-only edit.)
- [ ] WI 2.4 — Add an issue-row writer that runs BEFORE the commit-routing decision: for each open GH issue not yet in any tracker, append the row template. Iterate `OPEN_NUMS`; for each `N`, test membership with an **anchored** regex so `bug#23` doesn't match `#23`:
  ```bash
  if grep -qE '(^|[^0-9A-Za-z_])#'"$N"'($|[^0-9])' \
       "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null; then
    continue
  fi
  ```
  For the residual, fetch title+labels via `gh issue view "$N" --json title,labels`, parse via `grep -oE` (no jq), and append the row template to `ISSUES_PLAN.md`. Increment `NEW_RESEARCHED_COUNT` per row written.
- [ ] WI 2.5 — Add a cross-reference comment in the Standalone Sync section: `<!-- Bootstrap of empty $ZSKILLS_ISSUES_DIR/ happens in Phase 1a Sync; Standalone Sync inherits it via step 1's "Run Phase 1a" delegation. -->`
- [ ] WI 2.6 — Skill-version bump + mirror.

### Design & Constraints

Bootstrap fires unconditionally when `issues_dir` has zero trackers AND `OPEN_COUNT > 0`. If `OPEN_COUNT == 0`, sync exits early with a clean message — no empty tracker, no PR, no noise.

The bootstrap subroutine creates `$ZSKILLS_ISSUES_DIR` directory if missing.

Filename is `ISSUES_PLAN.md`. Row-writer regex is anchored so `bug#23` does not match `#23`.

### Acceptance Criteria

- [ ] AC-2.1 — `grep -nE 'ISSUES_PLAN\.md' skills/fix-issues/SKILL.md` returns ≥3 hits (existing line 521/525/542 patterns AND the new bootstrap-write site).
- [ ] AC-2.2 — `grep -nB1 -A8 'EXISTING_TRACKERS=' skills/fix-issues/SKILL.md | grep -E 'bootstrap|ISSUES_PLAN\.md'` returns ≥1 hit (bootstrap branch anchored to gap-detection site).
- [ ] AC-2.3 — `grep -nE 'OPEN_COUNT.*-eq 0|0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit (zero-issue early-exit).
- [ ] AC-2.4 — `grep -nE 'NOT YET RESEARCHED' skills/fix-issues/SKILL.md` returns ≥1 hit (row template).
- [ ] AC-2.5 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-2.6 — `bash scripts/skill-content-hash.sh skills/fix-issues` output matches the `metadata.version` suffix.
- [ ] AC-2.7 — `grep -nE 'Bootstrap of empty.*ISSUES_DIR|inherits.*bootstrap' skills/fix-issues/SKILL.md` returns ≥1 hit (WI 2.5 cross-reference).
- [ ] AC-2.8 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-2.9 — Row-writer membership check is anchored: `grep -nE '\(\^\|\[\^0-9A-Za-z_\]\)#' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-2.10 — Bootstrap heredoc renders YAML frontmatter at column 0. All three checks must pass: `grep -nE '^title: Issues — Auto-Bootstrapped Tracker$' skills/fix-issues/SKILL.md` returns ≥1; `grep -nE '^status: active$' skills/fix-issues/SKILL.md` returns ≥1; `grep -nE '^TRACKER$' skills/fix-issues/SKILL.md` returns ≥1 (terminator at column 0). Renders the simplification-pass invariant inline.

### Dependencies

Phase 1.

---

## Phase 3 — /land-pr dispatch + tracking marker on top of PREAMBLE-provided worktree

### Goal

Close the residual #233-adjacent gap PREAMBLE Phase 4 didn't cover: sync today commits in the worktree but doesn't dispatch `/land-pr` or open a PR. This phase adds the dispatch with a tracking marker so the orchestration is auditable.

### Dependencies (phase-specific)

Depends on PREAMBLE_WORKTREE_GATE.md Phase 4 (merged in commit `c1b0962`), specifically the `ensure-worktree.sh` preamble at top of `## Sync` and the `SPRINT_REPORT.md` commit at step 5. This phase inserts AFTER PREAMBLE's commit and BEFORE the existing Report block.

### Work Items

- [ ] WI 3.1 — Insert a new step in `skills/fix-issues/SKILL.md` `## Sync` AFTER PREAMBLE's `git -C "$TOPLEVEL" commit ...` line (~line 362) and BEFORE the existing "Report:" block (~line 366). The step does:

  1. Compute `SYNC_TS` (if not already in scope from PREAMBLE's preamble) and `SYNC_ID`:
     ```bash
     SYNC_TS="${SYNC_TS:-$(TZ=America/New_York date +%Y%m%d-%H%M%S)}"
     SYNC_ID="fix-issues.sync.${SYNC_TS}"
     ```
  2. Resolve `PIPELINE_ID` (derive if not in scope) and write the `requires.land-pr.${SYNC_ID}` marker on main_root:
     ```bash
     MAIN_ROOT="${MAIN_ROOT:-$(cd "$(git rev-parse --git-common-dir)/.." && pwd)}"
     PIPELINE_ID="${PIPELINE_ID:-fix-issues.${SYNC_TS}}"
     mkdir -p "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
     printf 'skill: land-pr\nrequired-by: fix-issues-sync\ndate: %s\n' \
       "$(TZ=UTC date -Iseconds)" \
       > "$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/requires.land-pr.${SYNC_ID}"
     ```
  3. Build PR body file and dispatch `/land-pr` via the Skill tool. Args mirror `skills/run-plan/modes/pr.md:339-348`:
     ```bash
     RESULT_FILE=$(mktemp)
     BODY_FILE=$(mktemp)
     {
       printf '## Summary\n`/fix-issues sync` on %s updated trackers.\n\n' "$(TZ=America/New_York date +%F)"
       printf '## Test plan\n- [x] Tracker diff reviewed by user before merge.\n'
     } > "$BODY_FILE"
     PR_TITLE="sync: $(TZ=America/New_York date +%F)"
     SYNC_BRANCH=$(git -C "$TOPLEVEL" rev-parse --abbrev-ref HEAD)
     LAND_ARGS="--branch=$SYNC_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sync --worktree-path=$TOPLEVEL --tracking-id=$SYNC_ID"
     # NO --auto. NO --no-monitor. Body intentionally OMITS GitHub auto-close
     # directives — sync closes approved issues itself via `gh issue close`
     # after /land-pr success.
     # Skill: { skill: "land-pr", args: "$LAND_ARGS" }
     ```
  4. Parse result-file via the canonical allow-list pattern:
     ```bash
     declare -A LP
     while IFS='=' read -r KEY VALUE; do
       case "$KEY" in
         STATUS|PR_URL|PR_NUMBER|PR_EXISTING|CI_STATUS|CI_LOG_FILE|\
         MERGE_REQUESTED|MERGE_REASON|PR_STATE|REASON|\
         CONFLICT_FILES_LIST|CALL_ERROR_FILE)
           LP["$KEY"]="$VALUE" ;;
         "") ;;
         *) printf 'WARN: /land-pr result has unknown key %q — ignoring\n' "$KEY" >&2 ;;
       esac
     done < "$RESULT_FILE"
     ```
  5. Verify `fulfilled.land-pr.${SYNC_ID}` is written by `/land-pr` only on `STATUS=merged` (the marker isn't written on `created`/`monitored` — that's by design; the orchestrator may re-run sync after CI completes to fulfill).

- [ ] WI 3.2 — `metadata.version` bump on `skills/fix-issues/SKILL.md` per the standard workflow.

- [ ] WI 3.3 — Mirror via `bash scripts/mirror-skill.sh fix-issues`.

### Design & Constraints

`SYNC_ID` is timestamp-derived (`fix-issues.sync.${SYNC_TS}`), stable across the single Bash invocation, unique per sync run. The `requires.*` marker is written AT dispatch time; the `--tracking-id` arg propagates the id to `/land-pr` so `fulfilled.land-pr.<id>` is written on successful merge — mirrors `/run-plan` PR-mode's pattern at `skills/run-plan/modes/pr.md:348` and `skills/run-plan/SKILL.md:888`.

### Acceptance Criteria

- [ ] AC-3.1 — `grep -nE 'requires\.land-pr\.\$\{?SYNC_ID' skills/fix-issues/SKILL.md` returns ≥1 hit in the sync section.
- [ ] AC-3.2 — `grep -nE '\-\-tracking-id.*SYNC_ID|--tracking-id.*sync\.' skills/fix-issues/SKILL.md` returns ≥1 hit; AND `awk '/^## Sync /,/^## /' skills/fix-issues/SKILL.md | grep -cE -- '--auto'` returns 0 (sync-section scoped; see AC-P.12 for rationale).
- [ ] AC-3.3 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-3.4 — `bash tests/test-skill-conformance.sh` exits 0.

### Dependencies

Phase 2.

---

## Phase 4 — Edge cases

### Goal

Verify and harden edge cases Phases 2-3 surface.

### Work Items

- [ ] WI 4.1 — Verify and add ACs for **zero open GH issues + empty issues_dir** → exits before bootstrap with `Sync complete. 0 open issues, no trackers needed.`
- [ ] WI 4.6 — Verify and add AC for **gh issue list failure handling** — non-zero exit surfaces stderr verbatim and sync exits non-zero.

### Design & Constraints

This phase is AC-only verification of Phases 2-3 edge cases. Hook-fail signals are real; never bypass.

### Acceptance Criteria

- [ ] AC-4.1 — `grep -nE '0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.6 — `grep -nE 'gh issue list.*failed|GH_OUT=\$\(gh issue list' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.9 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-4.10 — `bash tests/test-skill-conformance.sh` exits 0.

### Dependencies

Phases 2 and 3.

---

## Phase 5 — Final version verification, conformance, run-all (+ verifier-polish rebump)

### Goal

Verify the final state — version is current, conformance passes, full test suite passes, Progress Tracker is up to date. Handle the verifier-polish rebump case if a Phase-4 verifier subagent applied a content patch after the per-phase bump.

### Work Items

- [ ] WI 5.1 — **Verifier-polish detection + conditional rebump** per plan-wide Design & Constraints "Skill versioning workflow." No-op when hash matches; one rebump-commit when it doesn't.
- [ ] WI 5.2 — `bash scripts/mirror-skill.sh fix-issues` (idempotent — should be a no-op after WI 5.1). `diff -rq` empty.
- [ ] WI 5.3 — Full test suite captured to file (CLAUDE.md "Capture test output to a file, never pipe"):
  ```bash
  TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"
  mkdir -p "$TEST_OUT"
  bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1
  ```
  Read results; fix at originating phase on failure (no thrash — two attempts max).
- [ ] WI 5.4 — Conformance: `bash tests/test-skill-conformance.sh`. Fail loudly on non-zero.
- [ ] WI 5.5 — Update plan Progress Tracker rows for Phases 1-5 to ✓ with commit refs.
- [ ] WI 5.7 — Plan frontmatter `status: complete` is set by `/run-plan finish` at land time.

### Design & Constraints

No structural SKILL.md edits in Phase 5 — at most a one-line rebump. Test failures get fixed at originating phase, not band-aided here. Hook fires are real signals — investigate, don't bypass.

### Acceptance Criteria

- [ ] AC-5.1 — `grep -nE '^  version:' skills/fix-issues/SKILL.md | head -1` shows `version: "20[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}"`.
- [ ] AC-5.2 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-5.3 — `bash scripts/skill-version-stage-check.sh` exits 0.
- [ ] AC-5.4 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-5.5 — `bash tests/run-all.sh` exits 0; output captured to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`.
- [ ] AC-5.6 — Progress Tracker rows for Phases 1-5 show ✓ with commit refs.
- [ ] AC-5.7 — Content-hash matches version suffix.

### Dependencies

Phases 1-4 complete.

---

## Plan-level Tests (manual reproduction recipes)

The verifier-runnable ACs cover structural assertions. This manual recipe proves the actual behavior change end-to-end.

### Manual repro #231 (bootstrap)

1. In a scratch repo with `$ZSKILLS_ISSUES_DIR/` empty and at least one open GH issue:
   ```bash
   rm -rf .zskills/issues
   gh issue create --title "test bootstrap" --body "synthetic"
   /fix-issues sync
   ```
2. Expected (after this plan): `.zskills/issues/ISSUES_PLAN.md` is created with frontmatter header and ≥1 `### #NNN — <title>` row; research-agent dispatch runs; sync summary reports `K=1 tracker file(s) updated`.
3. Control (before this plan): no file is created; `K=0 trackers updated` reported silently.

### `/land-pr` failure recovery (AC-P.3)

1. Force a `/land-pr` failure.
2. Expected: sync reports `/land-pr STATUS=… REASON=…`, exits non-zero, GH issues approved at step 3 remain OPEN, tracker mods sit in the worktree.

### Conformance gate (CI)

`bash tests/test-skill-conformance.sh` exits 0. The cross-skill `/land-pr` caller check at lines 519-538 still passes.

---

## Plan Quality

**Drafting process.** /draft-plan (3 rounds) + /refine-plan (3 rounds) + 1 simplification pass + 1 focused refinement pass.

The focused refinement (Round 8) dropped `#233` — the sibling issue PREAMBLE_WORKTREE_GATE.md Phase 4 closed (merged commit `c1b0962`). Phase 3 of this plan narrowed to adding the residual `/land-pr` dispatch + tracking marker on top of PREAMBLE's commit; the bootstrap (#231) work in Phase 2 is unchanged.

**Key design decisions** (settled through review):

- **Bootstrap filename `ISSUES_PLAN.md`.** Existing sync glob, migration script, and skill-description all align on this name. Dashboard doesn't scan `issues_dir`, so filename has no dashboard effect.
- **Deferred close.** `gh issue close` runs only after `/land-pr` returns success. State divergence (GH closed but tracker unmerged) is impossible by construction.
- **No auto-close directives in plan/refinement PRs.** GitHub auto-closes from both PR body and commit messages at squash-merge, regardless of negation/quoting. AC-P.9a/b enforce zero hits on the plan-landing PR.
- **Tracking-marker symmetry with /run-plan PR mode.** Writes `requires.land-pr.<sync-id>` at dispatch + passes `--tracking-id` so `/land-pr` writes `fulfilled.land-pr.<sync-id>` on merge — mirrors `skills/run-plan/SKILL.md:888` + `skills/run-plan/modes/pr.md:348`.

**Remaining concerns:**

- `monitored` is reachable; `merged` is parsed defensively (unreachable without `--auto`). `*)` arms exit 1 fail-safe if `/land-pr` introduces a new STATUS value.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Outcome |
|-------|-------------------|---------------------------|---------|
| 1 (/draft-plan) | 15 | 14 | 23 fix + 4 justified (4 cross-dups) |
| 2 (/draft-plan) | 8 | 9 | 14 fix (3 cross-dups, 4 blockers fixed) |
| 3 (/draft-plan) | 2 polish | 5 substantive (2 blockers) | 3 fix + 1 doc + 1 residual |
| 4 (/refine-plan R1) | 7 defects + 3 meta + 4 stale-ref | 11 defects | 24 fix + 1 justified-not-fix |
| 5 (/refine-plan R2) | 8 (incl. framing pivot) | 9 | 14 fix + 3 folded; framing pivoted (a)→(c/d) |
| 6 (/refine-plan R3) | 3 | 5 | 5 fix + 2 residuals (N3.R3, DA3.5); all 4 verified blockers fixed |
| 7 (simplification) | — | — | Protected path collapsed to single bash block (~150 lines removed); state-file machinery deleted; AC-P.9 split into a/b/c/d (commit-message coverage); prose trim |
| 8 (/refine-plan R1, focused) | 13 in-scope findings | 12 in-scope findings | All resolved per disposition: dropped #233 / delegated to PREAMBLE / Phase 3 narrowed to /land-pr dispatch + tracking marker |

**Convergence grep (post-simplification + focused refinement).** `grep -nEi 'deterministic|hygiene[^a-z]|single-shot|caller is special|content-only|tracker edits are' docs/plans/FIX_ISSUES_SYNC_HARDENING.md`: `content-only` hits in the "Sync uses canonical monitor flow" subsection and "What this plan does NOT do" bullet (fix-cycle-agent rationale, principled). The prior `hygiene` rejection prose (formerly at line 17, in the bundle-rationale paragraph) was removed alongside the #233 drop — PREAMBLE Phase 4 closed the bundling pretext. No new unprincipled framings introduced.
