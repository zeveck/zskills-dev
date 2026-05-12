---
issues: [231, 233]
title: /fix-issues sync — bootstrap empty issues_dir + honor execution.main_protected
created: 2026-05-12
status: active
---

# Plan: /fix-issues sync — bootstrap empty issues_dir + honor execution.main_protected

> **Landing mode: PR** — This plan targets PR-based landing. All phases use worktree isolation with a named feature branch.

## Overview

`/fix-issues sync` has two correctness gaps that bundle naturally:

- **#231 — bootstrap gap.** When `$ZSKILLS_ISSUES_DIR/` has no tracker files (no `*_ISSUES.md`, no `ISSUES_PLAN.md`), `skills/fix-issues/SKILL.md:521,542` does `ls ... 2>/dev/null` and silently returns empty. The research-and-record loop has nothing to write into and silently no-ops; the sync summary reports `K=0 trackers updated` without flagging the gap.
- **#233 — `main_protected` violation.** Sync's prose at `skills/fix-issues/SKILL.md:282` ("**Commit** updated tracker files.") is implemented by the orchestrator as a bare `git commit` in whatever cwd the orchestrator started in (typically the main repo, branch `main`). Under `execution.main_protected: true`, the `block-direct-main-commit` hook at `hooks/block-unsafe-project.sh.template:475-477` deterministically denies the commit, leaving research blurbs written to the working tree with no way to land. `main_protected` is currently honored at admission for `direct` landing mode (`skills/fix-issues/SKILL.md:109-119`); sync was scoped pre-`main_protected` as a hygiene op and is exempt, but tracker files are versioned content and the boundary applies equally.

The two issues bundle because the #233 fix (route the step-5 commit through a worktree + `/land-pr` when `main_protected: true`) is what makes #231's bootstrap write safe under protection. Splitting would force either a partial fix or duplicate worktree plumbing.

## Acceptance Criteria (plan-level)

- [ ] AC-P.1 — `/fix-issues sync` on a repo with empty `$ZSKILLS_ISSUES_DIR/` and at least one open GH issue bootstraps a tracker file, populates it with the open issues, and runs the research-agent dispatch on those entries. The `K=0 trackers updated` silent-no-op from #231 is no longer reachable.
- [ ] AC-P.2 — `/fix-issues sync` on a repo with `execution.main_protected: true` and current branch in `{main, master}` does not attempt a direct `git commit` on the protected branch. Tracker-file commits are routed through a sync worktree branch + `/land-pr`.
- [ ] AC-P.3 — When the worktree+PR path is taken, `gh issue close` calls in Sync step 4 are deferred until AFTER `/land-pr` returns a success status (`created`, `monitored`, or `merged`). If `/land-pr` fails, no GitHub issues are closed (no state divergence).
- [ ] AC-P.4 — Sync producing zero net changes (no new issues, no closures, no annotations, no bootstrap write) is detected via `git status --porcelain` BEFORE worktree creation; sync exits cleanly with no PR.
- [ ] AC-P.5 — When `execution.main_protected: false` OR current branch is not `main`/`master`, sync executes the legacy direct-commit semantics (specified below — no pre-existing bash block exists; both paths are authored fresh by this plan).
- [ ] AC-P.6 — Both Standalone Sync (`skills/fix-issues/SKILL.md:183-295`) and Phase 1a Sync (`skills/fix-issues/SKILL.md:507-565`) bootstrap consistently. Sprint-mode auto-sync re-entry (`skills/fix-issues/SKILL.md:685-693`) also benefits from the step-5 fix because it re-enters standalone sync.
- [ ] AC-P.7 — `skills/fix-issues/SKILL.md` carries a current `metadata.version` after every commit (per-phase commits each bump; the final value is the hash of the final tree). `diff -rq skills/fix-issues .claude/skills/fix-issues` empty.
- [ ] AC-P.8 — `bash tests/run-all.sh` exits 0. `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-P.9a — The PR landing THIS plan does NOT include `Closes #231`/`#233` or `Fixes #231`/`#233` (or their bulleted / inline variants — GitHub auto-links these regardless of column position). Those closes belong to the implementation-landing PR (the one created by Phase 3 of this plan when run against this plan's worktree), NOT to a refinement/scaffolding PR. Verification (case-insensitive, verb forms, no `^` anchor — matches bulleted `- **Closes #231**`, inline `closes #231`, plain `Fixes #231`): `gh pr view <plan-PR> --json body --jq '.body' | grep -ciE '(close[sd]?|fixe[sd]?|resolve[sd]?) #(231|233)\b'` returns 0. (Background: a prior draft had this AC say the plan-landing PR SHOULD include `Closes #231`/`#233`; that conflated "PR that lands the plan file" with "PR that lands the implementation closing the issues." This plan separates them — the plan-file commit lands as bookkeeping, the implementation lands as Phase 3's `/land-pr` PR which is where the issue-close directives belong.)
- [ ] AC-P.9b — Runtime sync PRs (the ones produced by `/fix-issues sync` after this plan lands) do NOT include `Closes #N` for issues that step 4b already closed via the GitHub API (avoids redundant API calls at merge).
- [ ] AC-P.10 — Pre-existing uncommitted/untracked work in the main repo that is unrelated to sync (paths outside `$ZSKILLS_ISSUES_DIR/` and `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md`) is unaffected by sync's worktree-routing path.
- [ ] AC-P.11 — `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 after this plan lands. Baseline before plan = 0 (verified). The 2 new commit sites: Protected-path step 7 (commit on sync branch) and Direct-path commit. No additional `git commit` is introduced elsewhere in the skill. Locks in the "single sync commit logic in one spot, with two paths" invariant.
- [ ] AC-P.12 — Sync's `/land-pr` dispatch does NOT pass `--auto`. Verification (whole-file): `grep -cE -- '--auto' skills/fix-issues/SKILL.md` returns 0 (sync is human-review-only; merge happens manually after the user inspects the PR).

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Worktree setup + plan scaffold | ⬚ | | Branch + frontmatter + plan parses |
| 2 — Bootstrap detector for empty issues_dir | ⬚ | | #231 root site fix; covers both Sync paths |
| 3 — `main_protected` worktree routing in Sync step 5 | ⬚ | | #233 root site fix; authors step-5 bash from scratch |
| 4 — Edge cases: zero-issues, untracked-aware diff, stash discipline, rc surfacing | ⬚ | | Hardening + smoke test wired into run-all.sh |
| 5 — Final version verification, conformance, run-all | ⬚ | | Verify (or rebump on verifier polish) + full test pass |

## Design & Constraints (plan-wide)

### Bootstrap filename — `ISSUES_PLAN.md`

Bootstrap creates `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md`, the historical canonical name. Reasoning:

- **Sync's own glob** (`skills/fix-issues/SKILL.md:519-525, 542`) explicitly accepts `*ISSUES*.md` OR the literal `ISSUES_PLAN.md`. The literal form is the documented canonical name.
- **Path-migration script** (`skills/update-zskills/scripts/migrate-paths.sh:613`) lists `ISSUES_PLAN.md` first in its canonical issues-filenames array.
- **The dashboard does NOT scan `issues_dir`.** `skills/zskills-dashboard/scripts/zskills_monitor/collect.py` only walks `plans_dir` (`docs/plans/`) at lines 1143-1147 and 1249-1251. The `_ISSUES.md$` regex at line 482 categorizes files under `plans_dir`, never under `issues_dir`. So tracker filename has no effect on dashboard discovery, and the earlier "dashboard regex requires `_ISSUES.md` suffix" rationale was incorrect. (An earlier draft of this plan chose `GENERAL_ISSUES.md` for dashboard-compatibility reasons that turned out to be unfounded; reverted per the adversarial review.)
- **Skill description** (`skills/fix-issues/SKILL.md:31`) already names `ISSUES_PLAN.md` as a recognized discovery filename — no description-update WI needed.

Bootstrap header template (written ONCE, when the bootstrap subroutine fires; subsequent sync runs read the existing file):

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

Row format for the issue-rows-added-in-step-5 (sync step 4 writes these into the tracker, format mirrored from existing trackers in the wild):

```markdown
### #NNN — <issue title>

**Labels:** <comma-separated labels from `gh issue view`>
**Verdict:** NOT YET RESEARCHED

(research blurb added by step-6 research-agent dispatch)
```

This template makes the no-blurb case visible (`grep -B1 'NOT YET RESEARCHED'` lists every issue still awaiting research).

### `main_protected` routing — when and how

**Conditional on net-diff** (not unconditional). Sync runs are frequently no-ops (no new issues, no closures, no annotations, no bootstrap needed). Creating a worktree + opening a PR on every protected-main sync would produce constant noise PRs.

**Net-diff detector** (run after step 4 edits, before step 5 commit). Must detect both tracked-file modifications AND untracked new files (the bootstrapped file is untracked at this point). `SPRINT_REPORT.md` is a *secondary* annotation site sync sometimes touches (the existing prose at `skills/fix-issues/SKILL.md:280-295` lists it alongside tracker files); the path is included in the pathspec so non-empty diffs to it also trigger the routing, but it is not the primary payload — most sync runs only touch `$ZSKILLS_ISSUES_DIR/`. The pathspec tolerates the file being absent in a brand-new repo (no error from `git status --porcelain`):

```bash
SYNC_PATHS=("$ZSKILLS_ISSUES_DIR" "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
NET_DIFF=$(git status --porcelain -- "${SYNC_PATHS[@]}" 2>/dev/null)
if [ -z "$NET_DIFF" ]; then
  echo "Sync complete. No tracker changes."
  return 0  # within the sync flow, before step 5 (function-scoped exit; see "Recipe exit semantics" below)
fi
```

`git status --porcelain` covers `??` (untracked), `M ` (modified), `A ` (added), etc. — the bootstrap file shows as `??` and triggers the non-empty branch correctly. This obsoletes the earlier draft's `BOOTSTRAPPED` shell-variable approach (which would not persist across separate Bash tool invocations and depended on an ad-hoc flag).

**Routing decision** (after net-diff confirms there IS a change):

```bash
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." 2>/dev/null && pwd)}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
MAIN_PROTECTED=0
CONFIG_FILE="$PROJECT_ROOT/.claude/zskills-config.json"
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_CONTENT=$(cat "$CONFIG_FILE")
  if [[ "$CONFIG_CONTENT" =~ \"main_protected\"[[:space:]]*:[[:space:]]*true ]]; then
    MAIN_PROTECTED=1
  fi
fi
ON_PROTECTED_BRANCH=0
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
  ON_PROTECTED_BRANCH=1
fi
```

Both `main` and `master` are checked — `hooks/block-unsafe-project.sh.template:259` accepts either, and a repo with `master` as default branch and `main_protected: true` is a real (if rare) configuration. `$PROJECT_ROOT` is resolved with an explicit fallback to `git rev-parse --git-common-dir`, since the variable is not exported anywhere in `skills/fix-issues/SKILL.md` today; the existing consumers at lines 99/111 rely on harness env, and the new sync code must not silently fall back to "/" or empty on a fresh shell.

If `MAIN_PROTECTED == 1 && ON_PROTECTED_BRANCH == 1`: go to **Protected path**. Else: **Direct path**.

### Recipe exit semantics — orchestrator-prose STOP markers, not bare `exit N`

`skills/fix-issues/SKILL.md` is **orchestrator-prose, not a single bash script**. The orchestrator (Claude Code) reads the prose and executes each fenced bash block as a separate Bash tool invocation. A bare `exit 1` from one of those blocks exits **only that single bash invocation** — the orchestrator-level flow keeps running, and the next prose step's bash block executes anyway.

Throughout the Protected-path and Direct-path recipes, every error-handling clause emits an **explicit STOP marker** on stderr that the orchestrator-prose around it reads. The convention is:

1. The bash block prints `ERROR: <diagnostic>` to stderr and exits non-zero.
2. The surrounding prose says, in plain words: **"If you see `ERROR:` above, STOP — do not execute the subsequent bash blocks in this sync recipe. Surface the error to the user and exit the sync flow."**

The `exit N` calls in the bash blocks are kept (they propagate the failure to the Bash tool's exit code, which the orchestrator sees), but they are paired with explicit prose stops. An implementing agent that translates these blocks into SKILL.md prose must preserve **both** the `exit N` and the prose-stop line — neither alone is sufficient.

**STOP markers are advisory — they rely on the orchestrator reading them and obeying.** The cross-block state-file mechanism (see "Cross-block state persistence" below) provides structural enforcement on top of advisory STOP markers: each Protected-path block's head reads a sentinel file (`/tmp/sync-state-$SYNC_TS/proceed`) that the previous block writes only on success. A missing sentinel aborts the block immediately, regardless of whether the orchestrator obeyed the STOP marker. STOP markers remain the primary user-visible diagnostic; the sentinel guard is the structural backstop.

### Cross-block state persistence

Sync's Protected path runs as multiple separate Bash tool invocations. Shell variables do NOT persist across invocations. Use a filesystem state directory `/tmp/sync-state-$SYNC_TS/` to persist variables that downstream blocks need. Each block writes named files; each block that reads a variable does so via `cat /tmp/sync-state-$SYNC_TS/<name>.txt` (or equivalent). The state directory is created at sync start (step 0) and cleaned up at sync exit (successful or aborted) by the `.landed` write step (step 11) or the worktree-remove cleanup path.

**State files (one per variable):**

- `sync_ts.txt` — the `SYNC_TS` itself (written by WI 2.0 preamble). Defensive re-read source for blocks running in fresh Bash invocations.
- `open_nums.txt` — newline-separated open GH issue numbers (written by WI 2.1).
- `open_count.txt` — integer count of open issues (written by WI 2.1).
- `approved_list.txt` — newline-separated user-approved close numbers (written by the step-3 approval handler; producer guards on `[ "${#APPROVED_LIST[@]}" -gt 0 ]` — see "Variable derivation" for the empty-array round-trip discipline).
- `bootstrap_new.txt` — `yes`/`no` flag (written by the bootstrap subroutine; `yes` only when bootstrap wrote the file this run).
- `stash_ts.txt` — the `SYNC_TS` used for stash message anchoring (written by Protected-path step 2).
- `wt_path.txt` — the worktree path (written by Protected-path step 3-4 after the worktree exists or is resumed).
- `sync_branch.txt` — the timestamped `sync/$SYNC_TS` branch name (written by Protected-path step 3).
- `user_response.txt` — user's literal step-3 approval response (`231,233` / `all` / `none`; written by the step-3 prose handler, read by step-4 variable derivation).
- `new_researched_count.txt` — integer count of new tracker entries written by step 4's row-writer.
- `proceed` — sentinel file. Each Protected-path block writes this as its last action on success; the next block's first action is `[ -f /tmp/sync-state-$SYNC_TS/proceed ] || { echo "ERROR: prior block did not signal proceed; aborting" >&2; exit 1; }`. Each block also deletes the sentinel at its head after the guard passes, so successive blocks must each re-earn the proceed signal. This converts the advisory STOP marker into a structural gate. WI 2.0's preamble writes the initial sentinel so the first downstream block's guard passes.

**Helper conventions.** Each block uses:
```bash
SYNC_TS_FILE=/tmp/sync-state-$SYNC_TS
# read example:
OPEN_COUNT=$(cat "$SYNC_TS_FILE/open_count.txt")
# write example:
printf '%s\n' "${OPEN_NUMS[@]}" > "$SYNC_TS_FILE/open_nums.txt"
# proceed signal:
: > "$SYNC_TS_FILE/proceed"
```

The **Sync Preamble** (specified next, "Sync preamble — SYNC_TS + state directory bootstrap") creates `mkdir -p "$SYNC_TS_FILE"` once and writes the initial `proceed` sentinel so the first downstream block's guard passes. The preamble runs unconditionally on every sync invocation (Direct path AND Protected path) and is the sole producer of `$SYNC_TS`. The directory naming uses `$SYNC_TS` (defined in the preamble, NOT in Protected-path step 3) so concurrent sync runs do not collide. The cleanup step (`.landed` write in step 11 for the Protected path; the Direct path's final block for the Direct path; or the abort-handler `rm -rf "/tmp/sync-state-$SYNC_TS"` on any error exit — see "Sync preamble" for the abort-cleanup mandate) removes `/tmp/sync-state-$SYNC_TS` so `/tmp` does not accrete state directories.

### Sync preamble — SYNC_TS + state directory bootstrap

**This preamble runs as the very first bash block of every `/fix-issues sync` invocation, BEFORE Phase 1a gap-detection / bootstrap / WI 2.1 `gh issue list` / any state-file producer.** Both the Direct path and the Protected path share it. It is the sole producer of `$SYNC_TS` for the entire sync flow, so every downstream state-file reference resolves to a non-empty directory name:

```bash
SYNC_TS="$(TZ=America/New_York date +%Y%m%d-%H%M%S)"
mkdir -p "/tmp/sync-state-$SYNC_TS"
# Initial proceed sentinel so the first downstream block's guard passes:
: > "/tmp/sync-state-$SYNC_TS/proceed"
# Persist SYNC_TS for any downstream block that needs to recompute paths:
printf '%s\n' "$SYNC_TS" > "/tmp/sync-state-$SYNC_TS/sync_ts.txt"
```

**Failure mode this preamble prevents.** If `SYNC_TS` were defined later (e.g., at Protected-path step 3, as a prior draft had it), WI 2.1's `gh issue list` producer block would write to `/tmp/sync-state-/open_nums.txt` (literal empty interpolation under `$SYNC_TS`), and downstream consumers would later read from `/tmp/sync-state-<real-ts>/open_nums.txt` — finding nothing. The preamble closes that gap structurally.

**Abort-path cleanup mandate.** Every `ERROR:` clause that calls `exit N` in the recipes is responsible for `rm -rf "/tmp/sync-state-$SYNC_TS"` immediately before the `exit`, so a crashed sync does not accrete state dirs in `/tmp`. The successful-land path cleans up via step 11; the Direct path cleans up via its own final block (see "Direct path — author the legacy semantics"). The implementing agent MUST insert the `rm -rf` line before each abort-path `exit N` (or refactor into a `trap '... rm -rf ...' EXIT` if preferred, though `trap` only fires within a single Bash tool invocation, so the per-block-exit pattern is the canonical approach). Residual: an SIGKILL or container teardown between blocks would still leak the directory; that is an accepted residual (see Remaining concerns).

### Protected path — worktree + `/land-pr` + deferred close

Spec for step 5 under protection:

1. **Pre-flight stash check.** A stale stash from a previously-crashed protected sync would silently lose data on the next sync. Mirror the `pre-cherry-pick` discipline at `skills/fix-issues/SKILL.md:491-495`. Anchor the regex precisely so it doesn't false-positive on a user-authored stash message that happens to contain the literal phrase:
   ```bash
   if git stash list | grep -qE 'On [^:]+: pre-sync-worktree-[0-9]+$'; then
     echo "ERROR: leftover 'pre-sync-worktree-<ts>' stash from a prior sync. Resolve: git stash list; git stash pop <id> OR git stash drop <id>" >&2
     exit 1
   fi
   ```
   **Orchestrator STOP:** if you see `ERROR: leftover 'pre-sync-worktree-<ts>'` above, STOP — do not execute subsequent bash blocks in this sync recipe.
2. **Path-scoped stash** (NOT blanket `-u`). The user may have unrelated edits in `src/`, `docs/`, etc. — those must stay on main, not get swept into the sync worktree (CLAUDE.md "NEVER revert, discard, or 'clean up' changes you didn't make"). `git stash push -u` supports a pathspec and captures untracked files within that pathspec by itself — do NOT `git add -N` first (empirically: `add -N` followed by path-scoped `stash push -u` errors with `Entry not uptodate. Cannot merge.` and creates no stash). `SPRINT_REPORT.md` is conditionally included only if it exists, because `git stash push -u -- <pathspec>` errors with `pathspec did not match any file(s)` when no file at that path is staged, modified, or untracked:
   ```bash
   STASH_TS="$(date +%s)"
   STASH_PATHS=("$ZSKILLS_ISSUES_DIR/")
   if [ -e "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" ]; then
     STASH_PATHS+=("$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
   fi
   if ! git stash push -u -m "pre-sync-worktree-$STASH_TS" -- "${STASH_PATHS[@]}"; then
     echo "ERROR: stash push failed" >&2
     exit 1
   fi
   ```
   **Orchestrator STOP:** if you see `ERROR: stash push failed` above, STOP.
   Verified empirically: with the bootstrapped `$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md` left untracked (no `add -N`), `git stash push -u -- "$ZSKILLS_ISSUES_DIR/"` captures it, removes from working tree, and restores on pop intact. The earlier draft's `add -N` step turned out to break the stash; removed.
3. **Worktree path timestamped + branch name timestamped** (concurrency-safe). Two concurrent sync runs in the same project would otherwise share `WT_PATH=/tmp/${PROJECT_NAME}-sync` and corrupt each other's state when one expects a fresh worktree and the other is mid-operation. We timestamp the worktree path so concurrent runs do not collide, and we pass the timestamped slug as the create-worktree slug so the returned path matches. **`SYNC_TS` is NOT redefined here — it was set by the Sync preamble (see "Sync preamble — SYNC_TS + state directory bootstrap"). The state directory `/tmp/sync-state-$SYNC_TS/` already exists.** Re-read `SYNC_TS` from the state file in case this block runs in a fresh Bash tool invocation:
   ```bash
   SYNC_TS=$(cat "/tmp/sync-state-$SYNC_TS/sync_ts.txt" 2>/dev/null || echo "$SYNC_TS")
   PROJECT_NAME=$(basename "$PROJECT_ROOT")
   SYNC_BRANCH="sync/$SYNC_TS"
   SLUG="sync-$SYNC_TS"
   WT_PATH="/tmp/${PROJECT_NAME}-${SLUG}"
   PIPELINE_ID="fix-issues.sync.$SYNC_TS"
   ```
   Note: the bootstrap `cat ... 2>/dev/null || echo "$SYNC_TS"` pattern is the only place the state-file SYNC_TS is re-read defensively — once the preamble runs, `$SYNC_TS` is set in-process for the same Bash invocation, and persisted for any later one.
   On worktree resume (WT_PATH already exists from a crashed prior run with the *same* timestamp): `cd "$WT_PATH"` and verify `git rev-parse --abbrev-ref HEAD` matches `$SYNC_BRANCH` before continuing. On branch mismatch, abort with a clear diagnostic — resuming into a worktree on the wrong branch would commit to the wrong branch:
   ```bash
   if [ -d "$WT_PATH" ]; then
     RESUME_BRANCH=$(cd "$WT_PATH" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
     if [ "$RESUME_BRANCH" != "$SYNC_BRANCH" ]; then
       echo "ERROR: resume worktree $WT_PATH is on branch '$RESUME_BRANCH', expected '$SYNC_BRANCH'. Remove the stale worktree or wait for the prior sync to complete." >&2
       exit 1
     fi
     echo "Resuming existing sync worktree at $WT_PATH on $SYNC_BRANCH"
     cd "$WT_PATH"
   else
     # ... fall through to create-worktree.sh dispatch (next step)
     :
   fi
   ```
   **Orchestrator STOP:** if you see `ERROR: resume worktree ... is on branch` above, STOP.
4. **`create-worktree.sh` invocation + rc handling.** Pass the timestamped `$SLUG` (so the returned path matches `$WT_PATH`). Capture rc via `|| RC=$?` (errexit-neutral, no `set +e`/`set -e` pair needed):
   ```bash
   if [ ! -d "$WT_PATH" ]; then
     RC=0
     RESULT=$(bash "$CLAUDE_PROJECT_DIR/.claude/skills/create-worktree/scripts/create-worktree.sh" \
       --branch-name "$SYNC_BRANCH" \
       --pipeline-id "$PIPELINE_ID" \
       --purpose "fix-issues sync" \
       "$SLUG") || RC=$?
     case "$RC" in
       0)  WT_PATH="$RESULT"; cd "$WT_PATH" ;;
       2)  echo "ERROR: worktree path collision (rc=2). Inspect: ls -la /tmp/${PROJECT_NAME}-sync*" >&2; exit 2 ;;
       6)  echo "ERROR: fetch failed (rc=6). Re-run sync after network recovers." >&2; exit 6 ;;
       7)  echo "ERROR: local main has diverged from origin/main (rc=7). Pull or reset before re-running sync." >&2; exit 7 ;;
       10) echo "ERROR: local main is ahead of origin/main (rc=10). Resolve divergence (push or reset) and re-run sync." >&2; exit 10 ;;
       *)  echo "ERROR: create-worktree failed (rc=$RC). See stderr above." >&2; exit "$RC" ;;
     esac
   fi
   ```
   Each rc has a distinct diagnostic prefixed with `rc=N)` for greppable uniformity. No silent swallowing (memory: `feedback_or_true_pattern`). **Orchestrator STOP:** if you see any `ERROR: ... (rc=N)` line above, STOP.
5. **Pop stash inside the worktree.** Stashes are repo-shared so the entry is visible from any worktree of the same repo. Split missing-entry vs conflict so diagnostics don't mislead:
   ```bash
   STASH_REF=$(git stash list | grep "pre-sync-worktree-$STASH_TS" | head -1 | cut -d: -f1)
   if [ -z "$STASH_REF" ]; then
     echo "ERROR: pre-sync stash entry 'pre-sync-worktree-$STASH_TS' not found. Inspect: git stash list" >&2
     # Worktree was created but nothing to pop — clean up so the user isn't stuck with a dangling worktree.
     cd "$PROJECT_ROOT"
     if ! git worktree remove --force "$WT_PATH"; then
       echo "Note: worktree $WT_PATH could not be auto-removed; remove manually." >&2
     fi
     exit 1
   fi
   if ! git stash pop "$STASH_REF"; then
     echo "ERROR: stash pop conflicted in worktree (merge conflict). Inspect: cd $WT_PATH; git status; git stash list" >&2
     echo "Recovery: resolve conflicts in $WT_PATH then 'git stash drop $STASH_REF'; OR abandon: cd $PROJECT_ROOT; git worktree remove --force $WT_PATH; git stash pop $STASH_REF (re-apply on main)" >&2
     exit 1
   fi
   ```
   **Orchestrator STOP:** if you see `ERROR: pre-sync stash entry ... not found` OR `ERROR: stash pop conflicted` above, STOP.
6. **Stage explicit paths** (CLAUDE.md "When staging files, prefer adding specific files by name"):
   ```bash
   ADD_PATHS=("$ZSKILLS_ISSUES_DIR/")
   if [ -e "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" ]; then
     ADD_PATHS+=("$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
   fi
   git add -- "${ADD_PATHS[@]}"
   STAGED=$(git diff --cached --name-only)
   if [ -z "$STAGED" ]; then
     echo "Sync complete. No tracker changes after stash pop." >&2
     # Recover: pop unstashed nothing, no work to land, exit clean.
     cd "$PROJECT_ROOT"
     exit 0
   fi
   ```
7. **Commit on the sync branch** (no main-on-branch hook fire — worktree HEAD is `sync/$SYNC_TS`):
   ```bash
   git commit -m "sync: update trackers + research blurbs ($SYNC_TS)"
   ```
8. **Dispatch `/land-pr` via the Skill tool — canonical caller scaffold, no fix-cycle agent dispatch on CI failure.** Reuse the canonical caller's structural shape from `skills/fix-issues/modes/pr.md:80-220` (same-skill reference, not `quickfix`) for the **result-file parsing**, **STATUS case-arms**, AND the **monitor flow / CI_STATUS case-arms**. Sync does NOT pass `--no-monitor` — the canonical monitor flow runs and sync receives the authoritative CI status before returning to the user. In the `case "$CI_STATUS" in fail)` arm, sync does **not** dispatch a fix-cycle agent — the arm prints a punt diagnostic (with PR URL for manual user inspection) and terminates with `;;` so control falls through to step 11 cleanup (NOT `break`, which is invalid bash outside a loop).

   **Principled rationale for canonical monitor flow + no fix-cycle agent (Framing c/d):**

   The plan-wide Hard constraints assert `--auto` is never passed (AC-P.12) — sync is human-review-only. Within that posture, sync uses the canonical caller's monitor flow (it does NOT pass `--no-monitor`), because:
   - **CI failures should surface proactively** at PR creation time, not at merge time. A failing CI at sync time is a real signal the user wants to know about before reviewing the PR diff.
   - **4-of-5 canonical no-auto callers monitor.** `/commit pr`, `/do pr`, `/fix-issues pr`, and `/quickfix` (the 4 no-auto canonical caller skills) all retain the monitor flow even though they do not auto-merge. Sync's "interactive-by-design" posture is not a differentiator from those 4 callers; matching their structure is the conformance-aligned choice.
   - **Avoids documentation drift at `skills/land-pr/SKILL.md:320`.** That doc states "None of the 5 callers in this plan use `--no-monitor` — it is reserved for future callers." Keeping sync as a non-`--no-monitor` caller preserves this invariant.

   What sync DOES strip from the canonical caller scaffold is the **fix-cycle agent dispatch** on CI failure. The canonical fix-cycle agent (`skills/land-pr/references/fix-cycle-agent-prompt-template.md`) is specced for **code-and-test** PRs: read the CI log, diagnose, patch, commit. On a tracker-content PR, the agent has no legitimate "fix" to apply — a lint warning, a stale snapshot diff, or a flaky workflow failure would tempt it to mutate tracker entries, edit test workflows, or hallucinate fixes. The agent's prompt template explicitly assumes code+test scope, so dispatching it on a content PR violates the agent's design assumption.

   **No-precedent disclosure.** Sync is the **first canonical-caller variant to omit the fix-cycle agent dispatch entirely**. The other 5 callers (`/run-plan`, `/commit pr`, `/do pr`, `/fix-issues pr`, `/quickfix`) all default to `CI_MAX_ATTEMPTS=2` (verified at `skills/quickfix/SKILL.md:1076`: `MAX="${CI_MAX_ATTEMPTS:-2}"`) and dispatch on `CI_STATUS=fail` (verified at `skills/quickfix/SKILL.md:~1159`, inside the `fail)` arm). There is no existing canonical-caller variant with `CI_MAX_ATTEMPTS=0` posture — earlier drafts of this plan cited one incorrectly. The principled justification stands on its own without precedent: the canonical fix-cycle agent template at `skills/land-pr/references/fix-cycle-agent-prompt-template.md` is written for code+test PRs; on a content-only tracker PR, the agent has no legitimate fix to apply and is hazardous if invoked (it may mutate tracker entries to chase a stale snapshot diff, edit test workflows in search of a flaky-workflow fix, or hallucinate fixes against lint warnings). Sync's content-only posture is the rationale; precedent absence is acknowledged, not papered over.

   Sync therefore parses the full STATUS set the canonical caller handles (`skills/land-pr/SKILL.md` STATUS contract): `created`, `monitored`, `merged` (success values), plus `push-failed`, `create-failed`, `monitor-failed`, `merge-failed`, `rebase-conflict`, `rebase-failed`. The `monitored` value IS reachable under sync's no-`--no-monitor` posture — it is the canonical successful outcome when the monitor flow completes without auto-merging. `merged` is unreachable (sync does not pass `--auto`), but parsed defensively.

   **PR-body construction.** Use a quoted heredoc (`<<'EOF'`) for the literal template, then `printf` to substitute computed variables — prevents command injection from any future title text and keeps `$VAR` references in the static template unexpanded:
   ```bash
   RESULT_FILE=$(mktemp)
   BODY_FILE=$(mktemp)
   PR_DATE=$(TZ=America/New_York date +%F)
   PR_TS=$(TZ=America/New_York date -Iseconds)
   # APPROVED_LIST_RENDERED: space-separated bare numbers joined by ', ' for the body line,
   # or "(none)" if APPROVED_LIST array is empty. See "Variable derivation" below.
   if [ "${#APPROVED_LIST[@]}" -eq 0 ]; then
     APPROVED_LIST_RENDERED="(none)"
   else
     APPROVED_LIST_RENDERED=$(printf '#%s, ' "${APPROVED_LIST[@]}")
     APPROVED_LIST_RENDERED="${APPROVED_LIST_RENDERED%, }"
   fi
   {
     printf '## Summary\n'
     printf '`/fix-issues sync` on %s updated tracker files.\n\n' "$PR_DATE"
     printf -- '- Bootstrapped tracker: %s\n' "$BOOTSTRAP_NEW"
     printf -- '- New issues researched: %s\n' "$NEW_RESEARCHED_COUNT"
     printf -- '- Issues approved for close (will close after PR merge via API): %s — %s\n\n' "$APPROVED_CLOSE_COUNT" "$APPROVED_LIST_RENDERED"
     printf '## Test plan\n'
     printf -- '- [x] Tracker diff reviewed by user before merge (sync is interactive; CI runs post-merge against the merge commit, not as a sync gate)\n\n'
     printf '🤖 Generated by `/fix-issues sync` at %s\n' "$PR_TS"
   } > "$BODY_FILE"
   PR_TITLE="sync: trackers $PR_DATE"
   LAND_ARGS="--branch=$SYNC_BRANCH --title=\"$PR_TITLE\" --body-file=$BODY_FILE --result-file=$RESULT_FILE --landed-source=fix-issues-sync --worktree-path=$WT_PATH"
   # Dispatch (no --auto, no --no-monitor; canonical monitor flow runs):
   # Skill { skill: "land-pr", args: "$LAND_ARGS" }
   ```
   Note: the body intentionally does NOT include `Closes #N` lines — sync closes those issues itself via `gh issue close` in step 10 of this recipe, AFTER `/land-pr` returns success. Including `Closes #N` would cause GitHub to re-process the close at merge time, redundantly (and noisily in the audit log).

   **Post-land verification discipline.** `--auto` is NOT passed (AC-P.12). Per CLAUDE.md "Automerge BLOCKED is signal to act, not wait" memory: dispatching `--auto` and then walking away while merge is `BLOCKED` is a known failure mode. Sync explicitly side-steps that by **always** returning the PR URL for human review — no `--auto`, no merge expectation, no automerge-state polling. The user inspects the PR diff, decides to merge or close, and acts on GitHub. Sync's responsibility ends at "PR exists, URL reported."

   Variables `BOOTSTRAP_NEW`, `NEW_RESEARCHED_COUNT`, `APPROVED_CLOSE_COUNT`, `APPROVED_LIST` are computed inline during steps 3-4 from the user's approval set and sync's bookkeeping.
9. **Parse result with allow-list** (matches the canonical caller's `case` structure from `skills/fix-issues/modes/pr.md:115-151`):
   ```bash
   if [ ! -f "$RESULT_FILE" ]; then
     echo "ERROR: /land-pr produced no result file at $RESULT_FILE" >&2
     exit 1
   fi
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
   LAND_STATUS="${LP[STATUS]:-}"
   LAND_CI_STATUS="${LP[CI_STATUS]:-}"
   LAND_PR_URL="${LP[PR_URL]:-}"
   LAND_PR_NUMBER="${LP[PR_NUMBER]:-}"
   LAND_REASON="${LP[REASON]:-}"
   ```
   **Orchestrator STOP:** if you see `ERROR: /land-pr produced no result file` above, STOP.
10. **Step 4b — deferred GH issue close + CI-failure punt + CI-pending defer.** Only after `/land-pr` returns a success status AND CI passed (or is contract-equivalent to passed: `pass`, `none`, `skipped`, `not-monitored`, or empty) do we close GitHub issues that step 3 user-approved. Iterate `APPROVED_LIST` as a bash array (avoids word-splitting on `$IFS`). The CI_STATUS case-arms enumerate the FULL contract from `skills/land-pr/SKILL.md:162` and `skills/land-pr/scripts/pr-monitor.sh:120-125` (`CI_STATUS=pass|fail|pending|none|skipped|unknown|not-monitored`); the implementing agent MUST include an inline comment citing those line refs so future readers can verify the contract has not drifted. The success branch closes; the **defer** branch (`pending|unknown`) leaves issues open and emits a re-run-after-CI hint; the **punt** branch (`fail`) implements the content-PR punt (no fix-cycle agent dispatch — see step 8 rationale); the wildcard `*)` arm exits 1:
    ```bash
    case "$LAND_STATUS" in
      created|monitored|merged)
        # Inspect CI status. monitored is reachable (canonical monitor flow ran);
        # merged is unreachable in sync (no --auto) but parsed defensively.
        # CI_STATUS contract (per skills/land-pr/SKILL.md:162 and
        # skills/land-pr/scripts/pr-monitor.sh:120-125):
        #   pass|fail|pending|none|skipped|unknown|not-monitored
        # Sync mapping:
        #   - Success branch: ""|pass|none|skipped|not-monitored  → close GH issues, write .landed status:full
        #   - Defer branch:   pending|unknown                     → settle at pr-ready, DO NOT close GH issues
        #   - Punt branch:    fail                                → diagnostic with PR URL, DO NOT close GH issues, NO fix-cycle agent
        #   - Wildcard:       *                                   → defensive exit 1 with diagnostic
        case "$LAND_CI_STATUS" in
          ""|pass|none|skipped|not-monitored)
            echo "PR landed at $LAND_PR_URL (CI: ${LAND_CI_STATUS:-not-run})"
            # NOW close the approved issues — state-divergence safe.
            for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
              gh issue close "$ISSUE_NUM" --comment "Fixed; tracker updated in $LAND_PR_URL."
            done
            ;;
          pending|unknown)
            # CI is still running (pending) or the monitor returned an indeterminate
            # state (unknown — e.g., re-check returned an rc not in {0,1,8}). DO NOT
            # close GH issues yet — wait for CI to resolve and re-run sync, or have
            # the user inspect the PR on GitHub. The PR settles at pr-ready; sync
            # exits cleanly (no error) but flags the deferral.
            echo "PR created at $LAND_PR_URL — CI is $LAND_CI_STATUS." >&2
            echo "GH issues NOT closed yet (avoiding state divergence; close requires CI pass)." >&2
            echo "Re-run /fix-issues sync after CI completes, or close the approved issues manually:" >&2
            for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
              echo "  gh issue close $ISSUE_NUM --comment 'Fixed; tracker updated in $LAND_PR_URL.'" >&2
            done
            ;;
          fail)
            # Content-PR CI punt: no fix-cycle agent dispatch (see step 8 rationale —
            # the canonical fix-cycle agent template is specced for code+test, not content).
            # The case-arm naturally terminates with `;;` (NOT `break` — `break` outside a
            # loop is invalid bash and would fall through). After this arm, control flows
            # OUT of the case statement; step 11 (`.landed` write + state-dir cleanup +
            # Direct-path-style summary) handles the post-case wrap-up.
            echo "PR created at $LAND_PR_URL but CI failed (CI_STATUS=$LAND_CI_STATUS)." >&2
            echo "Sync's content PR does not dispatch a fix-cycle agent (the canonical agent" >&2
            echo "is specced for code+test PRs and would mutate trackers on lint/snapshot noise)." >&2
            echo "GH issues NOT closed (avoiding state divergence). Inspect the PR on GitHub:" >&2
            echo "  $LAND_PR_URL" >&2
            echo "If the failure is real, fix it on the sync branch and re-run sync." >&2
            echo "If the failure is unrelated (flaky workflow, infra), retry CI on the PR page." >&2
            ;;
          *)
            echo "ERROR: /land-pr returned unrecognized CI_STATUS=$LAND_CI_STATUS." >&2
            echo "GH issues NOT closed (avoiding state divergence). Inspect $RESULT_FILE and $LAND_PR_URL." >&2
            exit 1
            ;;
        esac
        ;;
      rebase-conflict)
        echo "/land-pr returned rebase-conflict. Resolve manually in $WT_PATH or re-run sync." >&2
        echo "GH issues NOT closed (avoiding state divergence)." >&2
        exit 1
        ;;
      push-failed|create-failed|monitor-failed|merge-failed|rebase-failed)
        echo "ERROR: /land-pr STATUS=$LAND_STATUS REASON=$LAND_REASON" >&2
        echo "GH issues NOT closed (avoiding state divergence). Re-run sync after resolving." >&2
        exit 1
        ;;
      *)
        echo "ERROR: /land-pr returned unrecognized STATUS=$LAND_STATUS REASON=$LAND_REASON" >&2
        echo "GH issues NOT closed (avoiding state divergence). Inspect $RESULT_FILE." >&2
        exit 1
        ;;
    esac
    ```
    **Orchestrator STOP:** if you see any `ERROR: /land-pr STATUS=...`, `/land-pr returned rebase-conflict`, or `ERROR: /land-pr returned unrecognized CI_STATUS` line above, STOP. A `CI failed (CI_STATUS=fail)` punt is NOT a STOP — sync surfaces the PR URL and exits cleanly, leaving the user to inspect. A `CI is pending` or `CI is unknown` defer is also NOT a STOP — sync exits cleanly without closing issues and the user re-runs sync (or runs the printed `gh issue close ...` commands manually) once CI resolves.

    Closes deferred to AFTER successful landing AND CI pass means a `/land-pr` failure or CI failure leaves GitHub state and tracker state both unchanged from before sync — no divergence to recover (verified design decision against the alternative of "close before land," which would leave GH closed but tracker unmerged on failure).
11. **Cleanup** — write `.landed` marker in worktree (CLAUDE.md "ALWAYS write a `.landed` marker"), then remove the state directory. The heredoc terminator MUST be at column 0 (no leading whitespace) when this block is inserted into `skills/fix-issues/SKILL.md`:
    ```bash
    cat > "$WT_PATH/.landed" <<MARKER
    status: full
    date: $(TZ=America/New_York date -Iseconds)
    source: fix-issues-sync
    pr: $LAND_PR_URL
    MARKER
    # Remove the cross-block state dir; the .landed marker is now the canonical
    # post-sync artifact for cleanup tools to key on.
    rm -rf "/tmp/sync-state-$SYNC_TS"
    ```

    **Posture: worktree at `$WT_PATH` is left in place after successful land.** The user may want to inspect the diff, re-run a check, or hand-edit the sync branch before merging on GitHub. The `.landed` marker is the cleanup signal — future cleanup tools (or the user) can prune `/tmp/<proj>-sync-*` worktrees that carry a `.landed` marker with `status: full`. On abort paths (failed stash pop, missing stash entry, CI fail), the worktree is either auto-removed (missing-entry case in step 5) or left in place for user inspection (CI-fail punt) — in either case, the `/tmp/sync-state-$SYNC_TS/` directory is removed by the abort handler that sets the error or by this cleanup step on success.

### Variable derivation (sync runtime state)

The Protected and Direct paths reference variables computed during sync's earlier steps. Each variable has **two manifestations**: an in-block shell variable (live within a single Bash tool invocation), and a state file under `/tmp/sync-state-$SYNC_TS/` (persists across Bash tool invocations — see "Cross-block state persistence" above). The producing block writes the state file; each downstream block reads it back via `cat` or `mapfile`.

- **`BOOTSTRAP_NEW`** — `yes` if the bootstrap wrote a new `ISSUES_PLAN.md` this run, `no` otherwise. Producer: WI 2.2 bootstrap subroutine. Persistence: `/tmp/sync-state-$SYNC_TS/bootstrap_new.txt`.
  ```bash
  # Producer (in bootstrap subroutine):
  if git status --porcelain -- "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" | grep -q '^??'; then
    BOOTSTRAP_NEW=yes
  else
    BOOTSTRAP_NEW=no
  fi
  printf '%s\n' "$BOOTSTRAP_NEW" > "/tmp/sync-state-$SYNC_TS/bootstrap_new.txt"
  # Consumer (PR-body construction in step 8):
  BOOTSTRAP_NEW=$(cat "/tmp/sync-state-$SYNC_TS/bootstrap_new.txt")
  ```
- **`APPROVED_LIST`** — bash array of bare integer issue numbers (no `#` prefix) the user approved at step 3. The orchestrator (Claude Code, executing sync's prose) captures the user's literal step-3 response, writes it to `/tmp/sync-state-$SYNC_TS/user_response.txt`, and the step-4 variable-derivation block parses it into `APPROVED_LIST` and also persists the array to `/tmp/sync-state-$SYNC_TS/approved_list.txt` (newline-separated bare integers). **Empty-array round-trip hazard.** A naive `printf '%s\n' "${APPROVED_LIST[@]}" > approved_list.txt` writes a single `\n` byte when the array is empty (bash expands `"${EMPTY[@]}"` to nothing, but the trailing `\n` of `printf '%s\n'` still fires once). The consumer's `mapfile -t APPROVED_LIST < approved_list.txt` then produces a **1-element array containing the empty string** rather than an empty array, and the downstream deferred-close loop calls `gh issue close ""` — a runtime error masking as a sync failure. The producer guards on `[ "${#APPROVED_LIST[@]}" -gt 0 ]`, AND the consumer applies a defense-in-depth empty-element filter:
  ```bash
  # Producer (step-3 prose handler writes the user's response to user_response.txt;
  # step-4 derivation parses it into the array AND persists to approved_list.txt):
  USER_RESPONSE=$(cat "/tmp/sync-state-$SYNC_TS/user_response.txt")
  APPROVED_LIST=()
  case "$USER_RESPONSE" in
    none) ;;
    all)  for N in "${ALL_FIXED_NUMS[@]}"; do APPROVED_LIST+=("$N"); done ;;
    *)    IFS=',' read -r -a APPROVED_LIST <<< "${USER_RESPONSE// /}" ;;
  esac
  # GUARD: empty-array round-trip — write 0 bytes, not a single \n. See AC-3.18.
  if [ "${#APPROVED_LIST[@]}" -gt 0 ]; then
    printf '%s\n' "${APPROVED_LIST[@]}" > "/tmp/sync-state-$SYNC_TS/approved_list.txt"
  else
    : > "/tmp/sync-state-$SYNC_TS/approved_list.txt"  # truncate to 0 bytes
  fi
  # Consumer (deferred-close loop in step 10, PR-body construction in step 8):
  mapfile -t APPROVED_LIST < "/tmp/sync-state-$SYNC_TS/approved_list.txt"
  # FILTER: defense-in-depth — drop empty elements that can arise if a producer
  # wrote a 1-byte newline-only file (e.g., a future producer that forgot the guard).
  _APPROVED_FILTERED=()
  for _X in "${APPROVED_LIST[@]}"; do
    [ -n "$_X" ] && _APPROVED_FILTERED+=("$_X")
  done
  APPROVED_LIST=("${_APPROVED_FILTERED[@]}")
  unset _APPROVED_FILTERED _X
  ```
  Both guards together prevent `gh issue close ""` regardless of which side regresses. The producer guard is the primary defense; the consumer filter survives a future producer-side bug.
- **`APPROVED_CLOSE_COUNT`** — `APPROVED_CLOSE_COUNT=${#APPROVED_LIST[@]}` (after mapfile-read above).
- **`NEW_RESEARCHED_COUNT`** — count of new tracker entries written by step 4's row-writer. Producer: step 4's row-writer loop increments and persists. Persistence: `/tmp/sync-state-$SYNC_TS/new_researched_count.txt`.
  ```bash
  # Producer (inside step-4 row-writer loop):
  printf '%d\n' "$NEW_RESEARCHED_COUNT" > "/tmp/sync-state-$SYNC_TS/new_researched_count.txt"
  # Consumer (PR-body construction in step 8):
  NEW_RESEARCHED_COUNT=$(cat "/tmp/sync-state-$SYNC_TS/new_researched_count.txt")
  ```
  Alternative: compute post-hoc from `grep -c '^### #' "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md` minus the pre-sync count (capture both before/after). Either method, the result lands in the state file.
- **`OPEN_NUMS`** / **`OPEN_COUNT`** — bash array of all currently-open GH issue numbers and its count. Producer: WI 2.1. Persistence: `/tmp/sync-state-$SYNC_TS/open_nums.txt` + `open_count.txt`.
  ```bash
  # Producer:
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}
  printf '%s\n' "${OPEN_NUMS[@]}" > "/tmp/sync-state-$SYNC_TS/open_nums.txt"
  printf '%d\n' "$OPEN_COUNT" > "/tmp/sync-state-$SYNC_TS/open_count.txt"
  # Consumer (downstream blocks):
  mapfile -t OPEN_NUMS < "/tmp/sync-state-$SYNC_TS/open_nums.txt"
  OPEN_COUNT=$(cat "/tmp/sync-state-$SYNC_TS/open_count.txt")
  ```
  This replaces the earlier draft's `grep -cE '"number"'`, which counts LINES (always 1 for single-line JSON) rather than matches. `grep -oE` emits one match per line; `mapfile` reads the array correctly.
- **`STASH_TS`**, **`SYNC_TS`**, **`WT_PATH`**, **`SYNC_BRANCH`** — set in Protected-path steps 2-4 and persisted to `stash_ts.txt`, the directory name itself (`/tmp/sync-state-$SYNC_TS/` encodes SYNC_TS), `wt_path.txt`, `sync_branch.txt` respectively. Downstream blocks (stash-pop, commit, land-pr dispatch, deferred-close, .landed write) read these from disk at the top of each block.

### Direct path — author the legacy semantics

Step 5 is **prose-only** in today's SKILL.md (lines 280-295: "**Commit** updated tracker files."). There is no pre-existing bash block. Both the Direct path and the Protected path are authored fresh by this plan. The Direct path implements the documented step-5 behavior literally:

```bash
ADD_PATHS=("$ZSKILLS_ISSUES_DIR/")
if [ -e "$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md" ]; then
  ADD_PATHS+=("$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md")
fi
git add -- "${ADD_PATHS[@]}"
STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
  echo "Sync complete. No tracker changes."
  exit 0
fi
# Gate close loop on commit success — mirror Protected-path divergence-safety.
if ! git commit -m "sync: update trackers + research blurbs"; then
  echo "ERROR: git commit failed in Direct path; not closing GH issues to avoid state divergence." >&2
  exit 1
fi
# Direct path closes happen here, as today (array iteration; not $IFS-split)
for ISSUE_NUM in "${APPROVED_LIST[@]}"; do
  gh issue close "$ISSUE_NUM" --comment "Fixed; tracker updated."
done
```

**Orchestrator STOP:** if you see `ERROR: git commit failed in Direct path` above, STOP — do not iterate the close loop.

### `/land-pr` dispatch contract — caller-list note

`/fix-issues sync` is NOT a new conformance-locked `/land-pr` caller. The conformance fingerprint at `tests/test-skill-conformance.sh:519-538` lists five files (`skills/run-plan/modes/pr.md`, `skills/commit/modes/pr.md`, `skills/do/modes/pr.md`, `skills/fix-issues/modes/pr.md`, `skills/quickfix/SKILL.md`) and asserts each contains the substring `land-pr`. The new sync dispatch lives in `skills/fix-issues/SKILL.md` — a different file from `modes/pr.md` — and adds a `land-pr` reference there, which neither breaks the substring check on the five tracked files (the five files are unaffected) nor adds a new entry to the tracked list. Verified at `tests/test-skill-conformance.sh:526-535` (the loop body).

### `gh issue list` failure handling

Throughout the new code, treat `gh issue list` non-zero exit as a hard error, NOT as "zero issues." A network failure or auth lapse must NOT silently skip the bootstrap or the gap detection:

```bash
GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1)
if [ "$?" -ne 0 ]; then
  echo "ERROR: 'gh issue list' failed:" >&2
  echo "$GH_OUT" >&2
  exit 1
fi
# Then count from GH_OUT, not from a fresh invocation.
```

**Orchestrator STOP:** if you see `ERROR: 'gh issue list' failed` above, STOP.

### Skill versioning workflow (per phase, plus a verifier-polish rebump path)

Each phase that edits `skills/fix-issues/SKILL.md` ends with its own version bump and commit. The PreToolUse hook `block-stale-skill-version.sh` enforces this at every commit; there is no way to defer the bump to a final phase. Phase 5 is primarily a **verification** step (the version on the final commit already reflects the final content hash; Phase 5 confirms it), BUT Phase 5 also handles the **verifier-polish-rebump** case: if Phase 4's verifier subagent applied a polish patch (typo fix, formatting nudge) and committed it, that polish commit's `metadata.version` may have a hash that no longer matches the final tree's content hash. Phase 5 detects the mismatch and emits a single rebump-commit on top:

```bash
# Per phase that edits SKILL.md (Phases 2, 3, 4):
HASH=$(bash scripts/skill-content-hash.sh skills/fix-issues)
TODAY=$(TZ=America/New_York date +%Y.%m.%d)
bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$TODAY+$HASH"
bash scripts/mirror-skill.sh fix-issues
git add skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
git commit -m "..."

# Phase 5 verifier-polish check + conditional rebump:
HASH_NOW=$(bash scripts/skill-content-hash.sh skills/fix-issues)
VER_NOW=$(bash scripts/frontmatter-get.sh skills/fix-issues/SKILL.md metadata.version | sed 's/.*+//')
if [ "$HASH_NOW" != "$VER_NOW" ]; then
  # Verifier polish (or any post-bump edit) shifted the hash. Rebump once.
  TODAY=$(TZ=America/New_York date +%Y.%m.%d)
  bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$TODAY+$HASH_NOW"
  bash scripts/mirror-skill.sh fix-issues
  git add skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
  git commit -m "polish: rebump skills/fix-issues metadata.version to current content hash"
fi
```

### Bootstrap fires regardless of caller — Phase 1a is shared

The bootstrap subroutine lives in Phase 1a Sync (lines ~538-548 region). Phase 1a is shared between standalone sync (`/fix-issues sync` step 1 delegates to Phase 1a) and sprint mode (`/fix-issues N`). Both flows now trigger bootstrap when issues_dir is empty.

In **sprint mode**, the bootstrap file is written to the main repo working tree at Phase 1a (before sprint creates per-issue worktrees). Sprint's later cherry-pick / PR-mode phases pick it up via the same `git status --porcelain` enumeration this plan uses for the net-diff check — so the bootstrap file rides along with whatever the sprint commits. Under `main_protected: true` in sprint mode, sprint's per-issue worktree+PR landing model is already worktree-routed, so the bootstrap file lands as part of a per-issue PR. No new commit path needed in sprint mode for the bootstrap.

In **standalone sync** (and in sprint-mode's "auto-sync before giving up" re-entry at `skills/fix-issues/SKILL.md:685-693`), the step-5 fix in Phase 3 of this plan covers both the bootstrap file and the tracker mods. Sprint-mode auto-sync re-entry IS covered — the implementing agent must NOT short-circuit Phase 3's routing based on "we are inside sprint mode."

### Hard constraints

- Do NOT call `gh pr create` or `gh pr merge --auto` directly (CLAUDE.md "Git Rules"). Dispatch `/land-pr`.
- Do NOT pass `--auto` to `/land-pr` from sync. Sync is human-review-only — the user reviews the PR and merges manually on GitHub after CI completes. Asserted by AC-P.12.
- Do NOT pass `--no-monitor` to `/land-pr` from sync. Sync uses the canonical caller's monitor flow so CI failures surface proactively at PR creation time (asserted by AC-3.8's negative `--no-monitor` check). On CI failure (`CI_STATUS=fail`), sync's case-arm prints a punt diagnostic and terminates with `;;` (falls through to step 11 cleanup) — it does NOT dispatch a fix-cycle agent (see plan-wide Design step 8 rationale: the canonical fix-cycle agent is specced for code+test PRs, hazardous on content). On `CI_STATUS` ∈ {`pending`, `unknown`}, sync's case-arm defers (PR settles at pr-ready; GH issues NOT closed; sync exits cleanly).
- Do NOT add a `jq` invocation to `skills/fix-issues/SKILL.md`. Use BASH_REMATCH on raw config JSON, matching the existing pattern at lines 101-105. (`gh issue list ... -q 'EXPR'` is a `gh` CLI flag, not a `jq` invocation; existing precedent at line 523 — the new code inherits this precedent, not extends it.)
- Do NOT bypass hooks with `--no-verify` (CLAUDE.md "Git Rules").
- Do NOT extend `main_protected` to landing modes other than sync — `direct` mode is already gated at lines 109-119.
- Do NOT extend the `block-direct-main-commit` hook tokenizer — Layer-1 carve-outs are accepted (CLAUDE.md / #225).
- `metadata.version` bump on each `skills/fix-issues/SKILL.md` edit is mandatory.
- The bash `exit N` calls in the recipes pair with explicit orchestrator-prose STOP markers (see "Recipe exit semantics" above) — an implementing agent must preserve both, since neither alone halts the orchestrator-level flow.

### What this plan does NOT do

- Does not refactor sync's argument parsing or research-agent dispatch logic.
- Does not change sprint-mode (`/fix-issues N`) per-issue commit semantics; that already routes through worktrees in Phase 3 onward.
- Does not add a `--auto` arg to sync (`skills/fix-issues/SKILL.md:42-43` — closing issues on GitHub requires human approval, and AC-P.12 asserts `--auto` is absent from sync's `/land-pr` dispatch).
- Does not modify Phase 1a Sync's COMMIT semantics — Phase 1a doesn't commit on its own (only step 5 does). Phase 2's edits to Phase 1a are scope-limited to gap-detection / bootstrap-write prose, not commit-flow changes.
- Does not dispatch a `/land-pr` fix-cycle agent on sync's PR. Sync's PR is content-only (tracker mods + research blurbs); a code-fix agent has no legitimate fix to apply to such content (see step 8 rationale).

---

## Phase 1 — Worktree setup + plan scaffold

### Goal

Establish the feature branch worktree this plan runs in and ensure `/run-plan` can parse the plan file. Bookkeeping-only; no behavior changes to `skills/fix-issues/SKILL.md`.

### Work Items

- [ ] WI 1.1 — Confirm the worktree at `/tmp/zskills-draftplan-fix-issues-sync-hardening` (or its rename) exists, the branch is `draftplan-fix-issues-sync-hardening` (or whatever the orchestrator agreed with the user), and it's pushed to `origin`.
- [ ] WI 1.2 — Confirm `docs/plans/FIX_ISSUES_SYNC_HARDENING.md` parses cleanly: frontmatter has `issues: [231, 233]`, `status: active`, Landing-mode blockquote is `PR`, phase headings use em-dash.
- [ ] WI 1.3 — Initial commit of the plan file on the feature branch (if not already committed).

### Design & Constraints

No `skills/fix-issues/SKILL.md` edits in this phase → no `metadata.version` bump.

### Acceptance Criteria

- [ ] AC-1.1 — `git rev-parse --abbrev-ref HEAD` returns the plan's feature branch name (not `main`/`master`).
- [ ] AC-1.2 — `head -10 docs/plans/FIX_ISSUES_SYNC_HARDENING.md | grep -E '^issues:'` returns a line with `[231, 233]`.
- [ ] AC-1.3 — `grep -nE '^## Phase [0-9]+ — ' docs/plans/FIX_ISSUES_SYNC_HARDENING.md` returns ≥5 phase headings with em-dash separator.
- [ ] AC-1.4 — `git log -1 --pretty=%s` includes the plan filename or a clear reference to it.

### Dependencies

None.

---

## Phase 2 — Bootstrap detector for empty `$ZSKILLS_ISSUES_DIR/`

### Goal

Close #231: when sync scans `$ZSKILLS_ISSUES_DIR/` and finds zero tracker files, bootstrap a `ISSUES_PLAN.md` file with the header template specified in plan-wide Design & Constraints. Cover the shared Phase 1a code path (which both Standalone Sync and Sprint Phase 1a call).

### Work Items

- [ ] WI 2.0 — **Sync preamble.** Insert a "Sync preamble" bash block at the very start of `skills/fix-issues/SKILL.md` Phase 1a Sync (immediately AFTER the Sync section heading at line 507, BEFORE any other Phase 1a logic — gap detection, WI 2.1's `gh issue list`, bootstrap, step 3 approval, step 5 routing). The block is shared by both Standalone Sync (delegates to Phase 1a per step 1) and Sprint Phase 1a. Verbatim shape per plan-wide Design & Constraints "Sync preamble — SYNC_TS + state directory bootstrap":
  ```bash
  SYNC_TS="$(TZ=America/New_York date +%Y%m%d-%H%M%S)"
  mkdir -p "/tmp/sync-state-$SYNC_TS"
  : > "/tmp/sync-state-$SYNC_TS/proceed"
  printf '%s\n' "$SYNC_TS" > "/tmp/sync-state-$SYNC_TS/sync_ts.txt"
  ```
  Rationale: makes `$SYNC_TS` available to WI 2.1's state-file writes (`open_nums.txt`, `open_count.txt`), the bootstrap subroutine's `bootstrap_new.txt` write, and every downstream Protected-path block. Without the preamble, WI 2.1 would write to `/tmp/sync-state-/` (literal empty interpolation) and Protected-path consumers would later read from `/tmp/sync-state-<real-ts>/` with no overlap.
- [ ] WI 2.1 — In `skills/fix-issues/SKILL.md` Phase 1a Sync, immediately before the gap-detection block at line 519-529 AND immediately after the preamble (WI 2.0), fetch the open-issue list AND count safely (single `gh` call, parsed for both count and number array). `grep -cE` over single-line JSON would return 0-or-1 (line count) — use `grep -oE | wc -l` for the actual match count, and `mapfile` for the number array:
  ```bash
  GH_OUT=$(gh issue list --state open --limit 500 --json number 2>&1)
  if [ "$?" -ne 0 ]; then
    echo "ERROR: 'gh issue list' failed:" >&2
    echo "$GH_OUT" >&2
    exit 1
  fi
  mapfile -t OPEN_NUMS < <(echo "$GH_OUT" | grep -oE '"number":[0-9]+' | sed 's/.*://')
  OPEN_COUNT=${#OPEN_NUMS[@]}
  ```
  **Orchestrator STOP:** if you see `ERROR: 'gh issue list' failed` above, STOP — do not run the bootstrap or step 5.
- [ ] WI 2.2 — Add the bootstrap subroutine before the existing `ls "$ZSKILLS_ISSUES_DIR"/*ISSUES*.md ...` at line 521. **The heredoc body must be inserted at column-0 indentation** when written into `skills/fix-issues/SKILL.md` — bash `<<TRACKER` (no `-` suffix) does not strip leading whitespace, and YAML frontmatter must start at column 0 to be parsed:
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

Created by \`/fix-issues sync\` on $TODAY because this repo had no tracker files in \`\$ZSKILLS_ISSUES_DIR/\` when sync ran. Split into domain-specific \`*_ISSUES.md\` files as patterns emerge — sync's glob picks them all up.

## Open Issues

(rows added by sync step 5 below)
TRACKER
    echo "Bootstrapped $ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md"
  fi
  ```
  (The heredoc body in this plan-spec block is shown dedented to column 0 to match how it must appear in SKILL.md. The surrounding `if` / `cat` lines retain their 2-space bash-block indent.)
- [ ] WI 2.3 — Update the prose at `skills/fix-issues/SKILL.md:558-561` to reflect that the structural cause of "Phase 2 prioritizes from bare titles" is closed; the self-warning may stay as historical context, but add: "Empty `issues_dir` now triggers bootstrap; this failure mode is structurally prevented." (Prose-only edit, no behavior change.)
- [ ] WI 2.4 — Add an issue-row writer that runs in step 5 BEFORE the commit-routing decision: for each open GH issue not yet in any tracker, append the row template. Iterate `OPEN_NUMS` (the array populated by WI 2.1); for each `N`, test membership across existing trackers with an **anchored** regex so `bug#23` doesn't match `#23` and a row for `#231` doesn't suppress writing `#23`:
  ```bash
  if grep -qE '(^|[^0-9A-Za-z_])#'"$N"'($|[^0-9])' \
       "$ZSKILLS_ISSUES_DIR"/*_ISSUES.md "$ZSKILLS_ISSUES_DIR/ISSUES_PLAN.md" 2>/dev/null; then
    continue
  fi
  ```
  For the residual, fetch title+labels via `gh issue view "$N" --json title,labels`, parse via `grep -oE` (no jq), and append to `ISSUES_PLAN.md` (or the appropriate `*_ISSUES.md` if one exists for the issue's domain — keep the existing "appropriate tracker" prose). Row template (column-0):
  ```markdown
  ### #NNN — <issue title>

  **Labels:** <comma-separated labels>
  **Verdict:** NOT YET RESEARCHED

  ```
- [ ] WI 2.5 — Add a cross-reference comment in the Standalone Sync section (lines 183-295) pointing to Phase 1a's bootstrap path: `<!-- Bootstrap of empty $ZSKILLS_ISSUES_DIR/ happens in Phase 1a Sync; Standalone Sync inherits it via step 1's "Run Phase 1a" delegation. -->`
- [ ] WI 2.6 — Skill-version bump + mirror (per the per-phase versioning workflow in plan-wide Design & Constraints).

### Design & Constraints

Bootstrap fires unconditionally when issues_dir has zero trackers AND `OPEN_COUNT > 0`. If `OPEN_COUNT == 0`, sync exits early with a clean message — no empty tracker, no PR, no noise.

The bootstrap subroutine creates `$ZSKILLS_ISSUES_DIR` directory if missing (handles the "issues_dir doesn't exist at all" edge case).

Filename is `ISSUES_PLAN.md`, NOT `GENERAL_ISSUES.md`. See plan-wide Design & Constraints for the dashboard-non-issue rationale.

The row-writer's membership-check regex is anchored so `bug#23` does not match `#23`. Past failure this prevents: an issue with body text mentioning `#231` being treated as already-tracked when the tracker actually has `#23`.

### Acceptance Criteria

- [ ] AC-2.0 — **Preamble present and ordered correctly.** `grep -nE 'SYNC_TS=' skills/fix-issues/SKILL.md` returns ≥1 hit, and the FIRST such hit's line number is LESS THAN the line number of the first `gh issue list --state open` hit (preamble runs before WI 2.1's `gh` call). Verification: `awk '/SYNC_TS=.*date \+/{p=NR; exit} END{exit !p}' skills/fix-issues/SKILL.md` succeeds AND its captured line number is below `grep -nE 'gh issue list --state open' skills/fix-issues/SKILL.md | head -1 | cut -d: -f1`. Also: `grep -nE 'mkdir -p "/tmp/sync-state-\$SYNC_TS"' skills/fix-issues/SKILL.md` returns ≥1 hit (state directory created in the preamble, NOT just referenced downstream).
- [ ] AC-2.1 — `grep -nE 'ISSUES_PLAN\.md' skills/fix-issues/SKILL.md` returns ≥3 hits (existing line 521/525/542 patterns AND the new bootstrap-write site).
- [ ] AC-2.2 — `grep -nB1 -A8 'EXISTING_TRACKERS=' skills/fix-issues/SKILL.md | grep -E 'bootstrap|ISSUES_PLAN\.md'` returns ≥1 hit (the bootstrap branch is anchored to the gap-detection site).
- [ ] AC-2.3 — `grep -nE 'OPEN_COUNT.*-eq 0|0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit (the zero-issue early-exit).
- [ ] AC-2.4 — `grep -nE 'NOT YET RESEARCHED' skills/fix-issues/SKILL.md` returns ≥1 hit (the row template for new entries).
- [ ] AC-2.5 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty (mirror in sync).
- [ ] AC-2.6 — `bash scripts/skill-content-hash.sh skills/fix-issues` output matches the `metadata.version` suffix in `skills/fix-issues/SKILL.md`.
- [ ] AC-2.7 — `grep -nE 'Bootstrap of empty.*ISSUES_DIR|inherits.*bootstrap' skills/fix-issues/SKILL.md` returns ≥1 hit in the Standalone Sync section (the cross-reference WI 2.5).
- [ ] AC-2.8 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-2.9 — Row-writer membership check is anchored: `grep -nE '\(\^\|\[\^0-9A-Za-z_\]\)#' skills/fix-issues/SKILL.md` returns ≥1 hit (the anchored regex is present, not a bare `#$N\b`).

### Dependencies

Phase 1.

---

## Phase 3 — `main_protected` worktree routing in Sync step 5

### Goal

Close #233: author step 5's bash block from scratch (currently prose-only at lines 280-295). The block has two paths — Protected and Direct — fully specified in plan-wide Design & Constraints. This phase implements them in `skills/fix-issues/SKILL.md` Standalone Sync.

### Work Items

- [ ] WI 3.1 — In `skills/fix-issues/SKILL.md` between the existing step 4 prose (lines 266-278) and the step 5 heading (line 280), insert the **net-diff detector** specified in plan-wide Design & Constraints (uses `git status --porcelain`, NOT `git diff --quiet`).
- [ ] WI 3.2 — Insert the **routing decision** block (PROJECT_ROOT resolution, MAIN_PROTECTED detection, ON_PROTECTED_BRANCH check on both `main` and `master`).
- [ ] WI 3.3 — Author the **Protected path** bash block in step 5, full specification per plan-wide Design & Constraints. Each numbered substep below maps 1:1 to the plan-wide Protected-path spec; orchestrator-prose STOP markers (see "Recipe exit semantics") are inserted alongside every `ERROR:` clause:
  1. pre-flight stash check for stale `pre-sync-worktree-<ts>` (anchored regex) + orchestrator STOP
  2. path-scoped `git stash push -u -m ... -- <sync-paths>` (NO `git add -N`; conditionally include `SPRINT_REPORT.md` only when it exists) + orchestrator STOP on stash-push failure
  3. compute timestamped `WT_PATH` (slug `sync-$SYNC_TS`) + timestamped `SYNC_BRANCH`; on `[ -d "$WT_PATH" ]` resume, verify branch matches `$SYNC_BRANCH` before continuing + orchestrator STOP on branch mismatch
  4. dispatch create-worktree.sh with rc handling (0, 2, 6, 7, 10, default) + orchestrator STOP on every non-zero rc
  5. stash pop in worktree with split missing-entry vs conflict diagnostics; auto-remove dangling worktree on missing-entry; verify the `git worktree remove --force` outcome (no `2>/dev/null` swallow) + orchestrator STOP
  6. explicit pathspec `git add` (conditionally including `SPRINT_REPORT.md`); empty-staged early-exit
  7. commit on sync branch
  8. dispatch `/land-pr` via Skill tool using the canonical caller scaffold (allow-list parser + full STATUS / CI_STATUS case-arms), **NOT passing `--auto` and NOT passing `--no-monitor`** (canonical monitor flow runs); PR-body construction via printf+heredoc; post-land verification discipline prose
  9. allow-listed result parsing (matches canonical caller's parser at `skills/fix-issues/modes/pr.md:115-126`) + orchestrator STOP on missing result file
  10. **deferred** `gh issue close` only on STATUS=`created|monitored|merged` AND `CI_STATUS` ∈ {empty, `pass`, `none`, `skipped`, `not-monitored`} per the full contract at `skills/land-pr/SKILL.md:162` / `skills/land-pr/scripts/pr-monitor.sh:120-125`; on `CI_STATUS` ∈ {`pending`, `unknown`}, **defer** with a re-run-after-CI hint (PR settles at pr-ready, GH issues NOT closed, sync exits cleanly with non-error rc but reports deferral); on `CI_STATUS=fail`, the case-arm terminates with `;;` (NOT `break`) and prints a content-PR punt diagnostic (no fix-cycle agent dispatch — see step 8 rationale); the wildcard `*)` arm `exit 1`s with a diagnostic. Cite `skills/land-pr/SKILL.md:162` as an inline comment. Explicit STATUS failure case-arms for `rebase-conflict`, `push-failed|create-failed|monitor-failed|merge-failed|rebase-failed`, and `*` (unrecognized); each non-success case-arm exits 1 + orchestrator STOP
  11. `.landed` marker write + state-dir `rm -rf "/tmp/sync-state-$SYNC_TS"`
- [ ] WI 3.4 — Author the **Direct path** bash block (the else branch) per plan-wide Design & Constraints — explicit `git add` pathspec (conditionally including `SPRINT_REPORT.md`), commit-success gate, immediate `gh issue close` (no defer needed — no separation between commit and close in this path) + orchestrator STOP on commit failure.
- [ ] WI 3.5 — Update the step-5 report block to surface either `LAND_PR_URL` (Protected path) or commit hash (Direct path).
- [ ] WI 3.6 — Skill-version bump + mirror.

### Design & Constraints

All concrete logic is specified in plan-wide Design & Constraints sections "Protected path" and "Direct path." This phase's job is to insert that logic into `skills/fix-issues/SKILL.md` at the right lines, with no design decisions deferred.

The single sync commit site remains step 5 — locked in by AC-P.11 (grep-count invariant).

`/fix-issues sync` is not a new conformance-locked `/land-pr` caller; the cross-skill conformance check at `tests/test-skill-conformance.sh:519-538` uses substring matching on five specific files and is unaffected by adding a `land-pr` reference inside `skills/fix-issues/SKILL.md` (a different file from the listed `skills/fix-issues/modes/pr.md`).

`--auto` is never passed (AC-P.12, plan-wide Hard constraints). `--no-monitor` is also NOT passed — sync uses the canonical caller's monitor flow so CI failures surface proactively at PR creation time. On `CI_STATUS=fail`, sync's case-arm prints a punt diagnostic and falls through with `;;` to step 11 cleanup (NOT `break` — invalid bash outside a loop; see step 10 inline comment). No fix-cycle agent dispatch (the canonical agent is specced for code+test PRs, hazardous on content). Rationale lives in plan-wide Design & Constraints step 8.

### Acceptance Criteria

- [ ] AC-3.1 — `grep -nE 'git status --porcelain -- "\$\{?SYNC_PATHS' skills/fix-issues/SKILL.md` returns ≥1 hit (net-diff detector uses status --porcelain, not diff --quiet).
- [ ] AC-3.2 — `grep -nE 'CURRENT_BRANCH.*==.*main.*\|\|.*CURRENT_BRANCH.*==.*master|ON_PROTECTED_BRANCH' skills/fix-issues/SKILL.md` returns ≥1 hit (both default-branch names handled).
- [ ] AC-3.3 — `grep -nE 'PROJECT_ROOT:-.*git-common-dir|git rev-parse --git-common-dir' skills/fix-issues/SKILL.md` returns ≥1 hit in the Standalone Sync section (PROJECT_ROOT has an explicit fallback).
- [ ] AC-3.4 — `grep -nE 'create-worktree\.sh' skills/fix-issues/SKILL.md` returns ≥1 hit in the Standalone Sync section. The slug passed to `create-worktree.sh` is the timestamped form `sync-$SYNC_TS` (NOT a bare `sync`), so concurrent sync runs do not collide: `grep -nE '\"sync-\$SYNC_TS\"|SLUG=\"sync-\$SYNC_TS\"' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-3.5 — `grep -cE 'land-pr|/land-pr' skills/fix-issues/SKILL.md` returns ≥2 (baseline = 0; the new Standalone Sync block adds at least 2 references — the dispatch comment and the LAND_ARGS construction). Sprint-mode caller pattern at `skills/fix-issues/modes/pr.md` is a different file, unaffected.
- [ ] AC-3.6 — `grep -cE 'gh pr create|gh pr merge --auto' skills/fix-issues/SKILL.md` returns 0 (no direct dispatch).
- [ ] AC-3.7 — `grep -nE 'pre-sync-worktree-' skills/fix-issues/SKILL.md` returns ≥2 hits (pre-flight check AND the new stash creation).
- [ ] AC-3.8 — **STATUS branch + CI_STATUS contract enumeration.** `grep -nE 'case "\$LAND_STATUS" in|created\|monitored\|merged\)' skills/fix-issues/SKILL.md` returns ≥1 hit (deferred-close success branch names all three success values from `/land-pr`'s STATUS contract, defensively). `grep -cE -- '--no-monitor' skills/fix-issues/SKILL.md` returns 0 (sync does NOT pass `--no-monitor`; canonical monitor flow is used so CI failures surface proactively — principled rationale at plan-wide Design & Constraints step 8). `grep -nE 'case "\$LAND_CI_STATUS" in' skills/fix-issues/SKILL.md` returns ≥1 hit. The CI_STATUS case-arms enumerate the FULL `/land-pr` CI_STATUS contract from `skills/land-pr/SKILL.md:162` / `skills/land-pr/scripts/pr-monitor.sh:120-125` (`pass|fail|pending|none|skipped|unknown|not-monitored`): `grep -nE '""\|pass\|none\|skipped\|not-monitored\)' skills/fix-issues/SKILL.md` returns ≥1 hit (success arm), `grep -nE 'pending\|unknown\)' skills/fix-issues/SKILL.md` returns ≥1 hit (defer arm), `grep -nE '^[[:space:]]*fail\)' skills/fix-issues/SKILL.md` returns ≥1 hit (punt arm — `fail` alone, NOT `fail|failure`; `failure` is not a contract value). `grep -nE 'CI_STATUS=fail|content-PR punt|fix-cycle agent' skills/fix-issues/SKILL.md` returns ≥1 hit (CI-fail arm with punt diagnostic). Cross-reference: `grep -nE 'skills/land-pr/SKILL\.md:162' skills/fix-issues/SKILL.md` returns ≥1 hit (the contract-source citation is in-skill so future readers can verify).
- [ ] AC-3.9 — `grep -nB3 -A2 'gh issue close' skills/fix-issues/SKILL.md | grep -E 'LAND_STATUS|case .*created\|monitored\|merged|after.*land'` returns ≥1 hit (`gh issue close` in the Protected path is documented as deferred).
- [ ] AC-3.10 — `grep -nE 'rc=10|ahead of origin/main' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-3.11 — `grep -nE '"\$\{APPROVED_LIST\[@\]\}"' skills/fix-issues/SKILL.md` returns ≥2 hits (APPROVED_LIST iterated as a bash array, not unquoted-word-split, in both Protected and Direct paths).
- [ ] AC-3.12 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-3.13 — `bash scripts/skill-content-hash.sh skills/fix-issues` matches the staged version suffix.
- [ ] AC-3.14 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-3.15 — Single sync commit site invariant: `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 (baseline = 0; one in Protected path step 7, one in Direct path). Spec at AC-P.11.
- [ ] AC-3.16 — `--auto` is NOT passed to sync's `/land-pr` dispatch: `grep -cE -- '--auto' skills/fix-issues/SKILL.md` returns 0 (whole-file check; AC-P.12 enforcement). The earlier awk-narrowed form used an invalid window pattern (the actual heading is `## Sync (if \`sync\` is present)`, not `## Sync$` or `## Standalone Sync`); whole-file is strictly stronger and avoids the false-pass risk.
- [ ] AC-3.17 — Failure case-arms exit non-zero and are paired with explicit prose STOP markers: `grep -nE 'rebase-conflict\)|push-failed\|create-failed\|monitor-failed\|merge-failed\|rebase-failed\)' skills/fix-issues/SKILL.md` returns ≥1 hit, AND `grep -nE 'STOP — do not execute|Orchestrator STOP' skills/fix-issues/SKILL.md` returns ≥3 hits (multiple STOP markers across the recipe).
- [ ] AC-3.18 — **APPROVED_LIST empty-array round-trip guard.** Producer guards on `[ "${#APPROVED_LIST[@]}" -gt 0 ]` before `printf '%s\n' "${APPROVED_LIST[@]}"`, and consumer filters empties after `mapfile`. Verification: `grep -nE '\[ "\$\{#APPROVED_LIST\[@\]\}" -gt 0 \]' skills/fix-issues/SKILL.md` returns ≥1 hit (producer guard) AND `grep -nE ': > "/tmp/sync-state-\$SYNC_TS/approved_list\.txt"' skills/fix-issues/SKILL.md` returns ≥1 hit (zero-byte truncate branch) AND `grep -nE '\[ -n "\$' skills/fix-issues/SKILL.md` returns ≥1 hit (consumer empty-element filter). Failure mode prevented: `gh issue close ""` runtime error when no issues were approved at step 3.

### Dependencies

Phase 2 (bootstrap path must exist before the worktree path can carry the bootstrapped file through to the PR).

---

## Phase 4 — Edge cases: zero-issues, untracked-aware diff, stash discipline, rc surfacing, gh-failure surfacing, executable smoke test

### Goal

Verify and harden the edge cases the design surfaces, AND add an executable smoke test that asserts the four most error-prone structural invariants directly against `skills/fix-issues/SKILL.md` (column-0 heredoc, no `add -N` regression, stash pathspec shape, single-commit-site invariant). The smoke test runs under `tests/run-all.sh` so it gates landing.

### Work Items

- [ ] WI 4.1 — Verify and add ACs for **zero open GH issues + empty issues_dir** → exits before bootstrap with `Sync complete. 0 open issues, no trackers needed.`
- [ ] WI 4.2 — Verify and add ACs for **zero net diff after step 4** → exits before worktree creation with `Sync complete. No tracker changes.`
- [ ] WI 4.3 — Verify and add ACs for **worktree resume** — timestamped `WT_PATH=/tmp/${PROJECT_NAME}-sync-${SYNC_TS}` (matches create-worktree.sh's `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}` with slug=`sync-${SYNC_TS}`); if `[ -d "$WT_PATH" ]`, verify branch matches before reusing. Branch-mismatch resume aborts with an explicit STOP.
- [ ] WI 4.4 — Verify and add ACs for **create-worktree.sh rc handling** (each of 0, 2, 6, 7, 10, default has a distinct branch with its own error message + orchestrator STOP).
- [ ] WI 4.5 — Add **non-main feature branch** path verification: `ON_PROTECTED_BRANCH=0 && MAIN_PROTECTED=1` falls through to the Direct path (commit on the feature branch — hook doesn't fire because the hook gate is "current branch is main/master"). The path-fall-through is NOT "the hook fires but is bypassed" — it is "the hook condition isn't met because we are not on main/master." Inline-comment so future readers don't add a redundant guard.
- [ ] WI 4.6 — Verify and add AC for **gh issue list failure handling** — non-zero `gh issue list` exit surfaces stderr verbatim and sync exits non-zero (NOT silent zero-fallback) + orchestrator STOP. Hook-fail and gh-fail are **real signals**, not noise to swallow: treat every non-zero rc as an abort condition with a diagnostic, never as a "best-effort, continue."
- [ ] WI 4.7 — Verify and add AC for **stash discipline**: pre-flight anchored-regex stash check + path-scoped `stash push -u -- <pathspec>` (NO `git add -N`) + post-pop missing-entry-vs-conflict split diagnostics + worktree cleanup on missing-entry failure + verified `git worktree remove` outcome (not silenced with `2>/dev/null`).
- [ ] WI 4.8 — Verify and add AC for **pre-existing unrelated working-tree edits are unaffected** — paths outside `$ZSKILLS_ISSUES_DIR/` and `$ZSKILLS_AUDIT_DIR/SPRINT_REPORT.md` stay on main (AC-P.10 enforcement).
- [ ] WI 4.9 — **Create `tests/test-fix-issues-sync-smoke.sh`** as a structural smoke test against `skills/fix-issues/SKILL.md`. The test runs `bash tests/test-fix-issues-sync-smoke.sh` from repo root and asserts (each as a separate `pass`/`fail` line):
  1. **Heredoc terminator AND body lines at column 0.** The bootstrap heredoc (`<<TRACKER`) terminator AND every YAML frontmatter body line must be unindented (column 0) for `cat <<TRACKER ... TRACKER` to emit a parseable YAML header. The test asserts each of:
     - `grep -cE '^TRACKER$' skills/fix-issues/SKILL.md` returns ≥1 (terminator at column 0).
     - `grep -cE '^title: Issues — Auto-Bootstrapped Tracker$' skills/fix-issues/SKILL.md` returns ≥1 (title at column 0).
     - `grep -cE '^status: active$' skills/fix-issues/SKILL.md` returns ≥1 (status at column 0).

     Failure mode: an implementing agent who copy-paste-indented the heredoc body (not just the terminator) breaks YAML frontmatter parsing in the bootstrapped tracker — checking only the terminator catches half the cases.
  2. **No `git add -N` in `skills/fix-issues/SKILL.md`.** `grep -cE 'git[[:space:]]+add[[:space:]]+-N' skills/fix-issues/SKILL.md` returns 0 (whole-file check — no narrow-window qualifier, since the Standalone Sync window cannot be reliably extracted from headings). Failure mode: empirically broken stash (see plan-wide Design & Constraints step 2 of Protected path).
  3. **Stash pathspec shape.** Exactly one `git stash push -u -m "pre-sync-worktree-...` invocation, and its pathspec includes `$ZSKILLS_ISSUES_DIR/` at minimum. Failure mode: blanket-`-u` stash sweeping unrelated user edits.
  4. **Single-commit-site invariant.** `grep -cE 'git[[:space:]]+commit' skills/fix-issues/SKILL.md` returns exactly 2 (AC-P.11 mirror).

  **Test-output format requirement (run-all.sh integration).** The final line of the smoke test's stdout MUST match the canonical `Results: N passed, M failed` format so `tests/run-all.sh:run_suite()` parses the counts correctly. Follow the convention at `tests/test-skill-content-hash.sh:135` exactly:
  ```bash
  printf 'Results: %d passed, %d failed (of %d)\n' "$PASS_COUNT" "$FAIL_COUNT" "$((PASS_COUNT + FAIL_COUNT))"
  if [ "$FAIL_COUNT" -gt 0 ]; then exit 1; fi
  exit 0
  ```
  Without this line, `run_suite`'s count extraction at `tests/run-all.sh:25` finds nothing and the smoke test's pass/fail contribution silently zeros — the test reports as "ran" but contributes 0 to the suite tally.
- [ ] WI 4.10 — **Wire the smoke test into `tests/run-all.sh`** by adding `run_suite "test-fix-issues-sync-smoke.sh" "tests/test-fix-issues-sync-smoke.sh"` to the suite list (alphabetically/contextually adjacent to other `test-fix-*` or `test-skill-*` entries — placement is implementation discretion, presence is the AC). This is the gating mechanism — without it, the smoke test is a manual recipe and the gap remains.
- [ ] WI 4.11 — Skill-version bump + mirror.

### Design & Constraints

This phase has two scopes: (a) AC-only verification of Phases 2-3 edge cases, and (b) the new executable smoke test. The smoke test is structural (grep-anchored, no git-runtime emulation) — it catches the four most common implementation slips the round-2 adversarial review identified as still-grep-passable-but-runtime-broken (column-0 heredoc; `add -N` regression; blanket stash; commit-count drift).

The smoke test does NOT attempt end-to-end behavior verification (would require a full scratch repo, GH stub, and a way to drive sync's interactive prompts). End-to-end behavior remains a follow-up canary (see Plan-level Tests § "Canary recipe — follow-up plan").

Hook-fail signals (block-stale-skill-version, block-direct-main-commit, etc.) are real signals to honor, never to bypass. If a hook fires during phase work, treat it as the agent's approach being wrong and find a legitimate path (CLAUDE.md memory: `feedback_hook_bypass`).

### Acceptance Criteria

- [ ] AC-4.1 — `grep -nE '0 open issues, no trackers needed' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.2 — `grep -nE 'No tracker changes' skills/fix-issues/SKILL.md` returns ≥1 hit.
- [ ] AC-4.3 — `grep -nE 'Resuming existing sync worktree|if \[ -d "\$WT_PATH"' skills/fix-issues/SKILL.md` returns ≥1 hit, AND `grep -nE 'resume worktree .* is on branch' skills/fix-issues/SKILL.md` returns ≥1 hit (branch-mismatch resume check).
- [ ] AC-4.4 — `grep -nE 'case "\$RC" in' skills/fix-issues/SKILL.md` returns ≥1 hit AND each rc error string uses the uniform `rc=N)` format: `grep -cE '\(rc=(2|6|7|10)\)' skills/fix-issues/SKILL.md` returns ≥4 (one per enumerated rc).
- [ ] AC-4.5 — `grep -nB1 -A3 'ON_PROTECTED_BRANCH=0|feature branch.*hook.*not.*fire|hook condition isn'"'"'t met' skills/fix-issues/SKILL.md | grep -E 'Direct path|hook only fires on main|not on main/master'` returns ≥1 hit (anchored — the prose reads "hook condition isn't met because we are not on main/master," not "hook fires but is bypassed").
- [ ] AC-4.6 — `grep -nE 'gh issue list.*failed|GH_OUT=\$\(gh issue list' skills/fix-issues/SKILL.md` returns ≥1 hit (gh failure handling at the bootstrap entry).
- [ ] AC-4.7 — `grep -nE 'git stash push -u -m.*pre-sync-worktree-.*--' skills/fix-issues/SKILL.md` returns ≥1 hit (path-scoped stash). `grep -cE 'git add -N' skills/fix-issues/SKILL.md` returns 0 (whole-file; the `add -N` step was empirically broken and removed — no narrow-window qualifier, since the Standalone Sync window cannot be reliably extracted from SKILL.md headings). `grep -nE 'stash entry .pre-sync-worktree-.* not found|stash pop conflicted' skills/fix-issues/SKILL.md` returns ≥1 hit (split diagnostics). `grep -nE 'if ! git worktree remove --force' skills/fix-issues/SKILL.md` returns ≥1 hit (the worktree-remove outcome is checked, not silenced).
- [ ] AC-4.8 — Manual verification (recorded in the commit message): with `git status -s` showing an unrelated edit outside sync paths, running sync's worktree path preserves that edit on main untouched. (Not all ACs need to be grep — this one is documented as a manual recipe in the plan-level Tests section.)
- [ ] AC-4.9 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-4.10 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-4.11 — **Smoke test exists and is wired into run-all.sh**:
  - File `tests/test-fix-issues-sync-smoke.sh` exists, is executable, and exits 0 against the current state of `skills/fix-issues/SKILL.md`.
  - `grep -q 'test-fix-issues-sync-smoke.sh' tests/run-all.sh` succeeds (the smoke test is invoked from the run-all driver, NOT just present as a standalone file).
  - The smoke test asserts each of the four invariants WI 4.9 specifies — invariant #1 expands into THREE column-0 checks (terminator, `title:`, `status:`), so the test emits **at least six** discrete `pass`/`fail` lines total (3 for invariant #1 + 1 each for invariants 2-4).
  - The test's final stdout line matches `Results: N passed, M failed` so `tests/run-all.sh:run_suite()` parses counts correctly: `tail -1 <smoke-stdout> | grep -qE '^Results: [0-9]+ passed, [0-9]+ failed'`.

### Dependencies

Phases 2 and 3.

---

## Phase 5 — Final version verification, conformance, run-all (+ verifier-polish rebump)

### Goal

Verify the final state — version is current, conformance passes, full test suite passes, Progress Tracker is up to date. Handle the **verifier-polish-rebump** edge case: if any prior phase's verifier subagent applied a content patch after the phase's own version bump, the final tree's content hash will not match the staged version. This phase detects the mismatch and emits a single rebump commit.

### Work Items

- [ ] WI 5.1 — **Verifier-polish detection + conditional rebump.** Compute the current content hash and compare against the suffix in `skills/fix-issues/SKILL.md`'s `metadata.version`. If they match (the common case — no verifier polish since the last per-phase bump), this is a no-op. If they don't match (verifier polish shifted the hash), apply the rebump-once recipe from plan-wide Design & Constraints "Skill versioning workflow":
  ```bash
  HASH_NOW=$(bash scripts/skill-content-hash.sh skills/fix-issues)
  VER_SUFFIX=$(bash scripts/frontmatter-get.sh skills/fix-issues/SKILL.md metadata.version | sed 's/.*+//')
  if [ "$HASH_NOW" != "$VER_SUFFIX" ]; then
    TODAY=$(TZ=America/New_York date +%Y.%m.%d)
    bash scripts/frontmatter-set.sh skills/fix-issues/SKILL.md metadata.version "$TODAY+$HASH_NOW"
    bash scripts/mirror-skill.sh fix-issues
    git add skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
    git commit -m "polish: rebump skills/fix-issues metadata.version to current content hash"
  fi
  ```
  If they match, do nothing — no commit, no churn. The PreToolUse hook `block-stale-skill-version.sh` makes the "match" case the structural norm; the rebump is a recovery path for the verifier-polish case only.
- [ ] WI 5.2 — `bash scripts/mirror-skill.sh fix-issues` (idempotent re-mirror — should be a no-op after WI 5.1). `diff -rq skills/fix-issues .claude/skills/fix-issues` empty.
- [ ] WI 5.3 — Full test suite: `TEST_OUT="/tmp/zskills-tests/$(basename "$(pwd)")"; mkdir -p "$TEST_OUT"; bash tests/run-all.sh > "$TEST_OUT/.test-results.txt" 2>&1`. Read results; if any failure, stop and fix at originating phase (no thrash — two attempts max per CLAUDE.md). Includes the new `tests/test-fix-issues-sync-smoke.sh` wired in Phase 4.
- [ ] WI 5.4 — Conformance: `bash tests/test-skill-conformance.sh`. Fail loudly on non-zero.
- [ ] WI 5.5 — Update plan Progress Tracker rows for Phases 1-5 to ✓ with commit refs.
- [ ] WI 5.6 — **Commit the canary follow-up stub.** Verify `docs/plans/FIX_ISSUES_SYNC_CANARY.md` exists with frontmatter `status: draft` and contains the canary recipe specified in Plan-level Tests § "Canary recipe — follow-up plan." Commit it on the feature branch so the implementation PR carries the follow-up artifact. Verification: `head -10 docs/plans/FIX_ISSUES_SYNC_CANARY.md | grep -E '^status: draft'` succeeds; `grep -q 'main_protected' docs/plans/FIX_ISSUES_SYNC_CANARY.md` succeeds.
- [ ] WI 5.7 — Plan frontmatter `status: complete` is set by `/run-plan finish` at land time (not by this phase).

### Design & Constraints

Phase 5 makes no structural SKILL.md edits — at most a one-line `metadata.version` rebump in the verifier-polish-shifted-hash case. If the verifier polish path fires, it is a single commit followed by mirror + diff verification.

If any test failure surfaces in Phase 5, fix at the originating phase. Don't band-aid in Phase 5.

A hook fire during Phase 5 (e.g., `block-stale-skill-version.sh` denying a commit) is a real signal: it means the WI 5.1 rebump logic is wrong or the staged content drifted. Investigate; do not bypass.

### Acceptance Criteria

- [ ] AC-5.1 — `grep -nE '^  version:' skills/fix-issues/SKILL.md | head -1` shows `version: "20[0-9]{2}\.[0-9]{2}\.[0-9]{2}\+[0-9a-f]{6}"`, with date = today (or the most-recent-phase commit date) in `America/New_York`.
- [ ] AC-5.2 — `diff -rq skills/fix-issues .claude/skills/fix-issues` returns empty.
- [ ] AC-5.3 — `bash scripts/skill-version-stage-check.sh` exits 0 (no stale-version mismatch when nothing is staged this phase). If WI 5.1's rebump fired and was committed, the staged tree is empty at this AC's evaluation and the check still passes.
- [ ] AC-5.4 — `bash tests/test-skill-conformance.sh` exits 0.
- [ ] AC-5.5 — `bash tests/run-all.sh` exits 0; output captured to `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt`. The captured output includes a `Tests: test-fix-issues-sync-smoke.sh` section with all four invariants passing.
- [ ] AC-5.6 — Progress Tracker rows for Phases 1-5 show ✓ with commit refs.
- [ ] AC-5.7 — Content-hash matches version suffix: `bash scripts/skill-content-hash.sh skills/fix-issues` output equals the `+HASH` portion of `skills/fix-issues/SKILL.md`'s `metadata.version` (verifier-polish rebump correctly applied OR was unnecessary).
- [ ] AC-5.8 — `docs/plans/FIX_ISSUES_SYNC_CANARY.md` exists, parses cleanly, and has `status: draft` in its frontmatter. `git log --oneline -- docs/plans/FIX_ISSUES_SYNC_CANARY.md` shows ≥1 commit on the feature branch (the stub is part of the implementation PR).

### Dependencies

Phases 1-4 complete.

---

## Plan-level Tests (manual reproduction recipes + canary deferral)

The verifier-runnable ACs above cover the structural assertions. The Phase 4 smoke test (`tests/test-fix-issues-sync-smoke.sh`, wired into `tests/run-all.sh`) gates the four most error-prone structural invariants at CI time. These manual recipes prove the actual behavior change end-to-end and serve as the test plan for the landing PR (AC-P.9a) and any future regression checks.

### Manual repro #231 (bootstrap)

1. In a scratch repo with `$ZSKILLS_ISSUES_DIR/` empty (or nonexistent) and at least one open GH issue:
   ```bash
   rm -rf .zskills/issues
   gh issue create --title "test bootstrap" --body "synthetic"
   /fix-issues sync
   ```
2. Expected (after this plan): `.zskills/issues/ISSUES_PLAN.md` is created with the frontmatter header and at least one `### #NNN — <title>` row; research-agent dispatch runs against the new entries; sync summary reports `K=1 tracker file(s) updated`.
3. Expected (before this plan, control): no file is created; `K=0 trackers updated` is reported silently.

### Manual repro #233 (main_protected)

1. In a repo with `.claude/zskills-config.json` containing `execution.main_protected: true`, on branch `main`, with at least one open GH issue not yet in any tracker:
   ```bash
   git checkout main
   /fix-issues sync
   ```
2. Expected (after this plan): sync detects `MAIN_PROTECTED=1 && ON_PROTECTED_BRANCH=1`, runs the net-diff check (non-empty due to bootstrap or tracker mods), pre-flight-checks stash, path-scoped stashes tracker dir + sprint report (only if it exists), creates worktree at `/tmp/<proj>-sync-YYYYMMDD-HHMMSS/` on branch `sync/YYYYMMDD-HHMMSS`, pops stash there, commits, dispatches `/land-pr` (canonical monitor flow, no `--auto`, no `--no-monitor`), parses STATUS=`monitored` (CI ran successfully) or STATUS=`created` with `CI_STATUS` set from the result file, defers `gh issue close` until success-AND-CI-pass. Reports the PR URL in the summary. On `CI_STATUS=fail`, sync prints a punt diagnostic and falls through to cleanup; no fix-cycle agent is dispatched. On `CI_STATUS` ∈ {`pending`, `unknown`}, sync defers issue-close and emits a re-run-after-CI hint. The user reviews the PR on GitHub and merges manually.
3. Expected (before this plan, control): sync attempts `git commit` on main, the `block-direct-main-commit` hook denies it, sync exits with the hook's deny envelope visible, research blurbs remain in the main repo working tree uncommitted.

### Regression test for non-protected path

1. In a repo with `execution.main_protected: false`, on `main`, with a new GH issue:
   ```bash
   /fix-issues sync
   ```
2. Expected: sync's Direct path commits tracker mods directly on main (commit succeeds because hook is off), runs `gh issue close` for any approved closes. No worktree, no PR.

### Pre-existing unrelated edits regression (AC-P.10)

1. With `main_protected: true` on `main`, make an unrelated edit:
   ```bash
   echo "wip note" >> docs/README.md
   git status -s  # should show ' M docs/README.md'
   /fix-issues sync
   ```
2. Expected: after sync completes (Protected path), `git status -s` in the main repo still shows ` M docs/README.md` — sync's path-scoped stash didn't touch it, and the worktree didn't sweep it in.

### `/land-pr` failure recovery (AC-P.3)

1. Force a `/land-pr` failure (e.g., set `--branch` to a name that already has a closed PR with merge conflicts, or simulate by deleting the worktree mid-flight).
2. Expected: sync reports `/land-pr STATUS=… REASON=…`, exits non-zero, GH issues approved at step 3 remain OPEN on GitHub, tracker mods sit in the worktree (and stash, if pop failed). User can re-run sync after resolving.

### Conformance gate (CI)

`bash tests/test-skill-conformance.sh` exits 0. The cross-skill `/land-pr` caller check at lines 519-538 still passes (5 listed files unchanged; the new `land-pr` reference inside `skills/fix-issues/SKILL.md` adds a substring hit but doesn't break the assertion).

### Canary recipe — follow-up plan, NOT a hard AC

A full end-to-end canary that drives `/fix-issues sync` against a scratch repo with `main_protected: true`, a synthetic open issue, and verifies the PR is opened correctly is **valuable but not blocking**. It is structured as a **follow-up plan**, not a hard AC of this plan, because:

- `/run-plan auto` cannot autonomously execute `/fix-issues sync` against a scratch repo — sync is interactive and requires the user's step-3 approval response.
- Making canary success a hard AC would deadlock the auto-mode pipeline of THIS plan.

**Deferral mechanism.** This plan ships a `status: draft` follow-up plan stub at `docs/plans/FIX_ISSUES_SYNC_CANARY.md` (committed by Phase 5 WI 5.6). The stub carries the canary recipe verbatim from the recipe below; when a future agent runs `/draft-plan` against it or `/run-plan auto` is invoked on it, the follow-up plan is fleshed out and the canary is exercised end-to-end. This plan's `status: complete` transition is NOT blocked by the canary follow-up — the stub artifact lands with the implementation PR, the follow-up execution is async.

**Recipe to emit on land (orchestrator's responsibility, not a verifier-gated AC):**

```bash
# In a freshly-created scratch repo:
mkdir -p /tmp/fix-issues-sync-canary && cd /tmp/fix-issues-sync-canary
git init -q && git commit --allow-empty -m "init" -q
gh repo create --private --source=. --remote=origin --push
cat > .claude/zskills-config.json <<JSON
{"execution":{"main_protected":true}}
JSON
mkdir -p .zskills/issues
gh issue create --title "canary: bootstrap+protected sync" --body "synthetic"
# Now run /fix-issues sync interactively and verify:
#  1. Bootstrap creates .zskills/issues/ISSUES_PLAN.md with frontmatter at col 0
#  2. Net-diff detector fires, routes to Protected path
#  3. Worktree created at /tmp/fix-issues-sync-canary-sync-YYYYMMDD-HHMMSS
#  4. PR opened with `sync: trackers <date>` title, no `Closes #N` in body
#  5. After human-approves the merge on GitHub, gh issue close fires
```

The orchestrator emits this recipe to the user in the land-time report. The user runs it at their convenience.

---

## Plan Quality

**Drafting process:** /draft-plan with up to 3 rounds of adversarial review, followed by /refine-plan with 1+ additional rounds (this revision).

**Round-1 findings + dispositions:** 29 total findings (15 reviewer + 14 devil's advocate, 4 cross-duplicates). 23 fix-required + 4 justified-not-fix. Disposition at `/tmp/draft-plan-review-FIX_ISSUES_SYNC_HARDENING-round-1.md`.

**Round-2 findings + dispositions:** 17 new findings (8 reviewer + 9 devil's advocate, 3 cross-duplicates). 4 new blockers (R2.1 OPEN_COUNT grep semantics, R2.2 indented heredoc, DA2.1 wrong WT_PATH from --prefix, DA2.2 broken `add -N` + stash). All blockers + majors + minors fixed in the round-2 refinement. Disposition at `/tmp/draft-plan-review-FIX_ISSUES_SYNC_HARDENING-round-2.md`.

Round 2 found real structural bugs in the round-1 spec (broken stash recipe; wrong worktree path math; YAML frontmatter rendered at column 2 → invalid). These were empirically reproduced before fixing.

**Round-3 findings + dispositions:** Reviewer side declared CONVERGED with 1 minor + 1 nit (N3.1 set -e fragility on `$?`-after-substitution, N3.2 `2>/dev/null` on `git worktree remove` swallows useful stderr — folded into Phase 3 implementation as polish items). DA side found 2 blockers + 1 major + 2 minors: DA3.1 missing `monitored` in deferred-close case-statement (would misclassify the canonical successful no-auto-CI-pass outcome as failure); DA3.2 entangled `--no-monitor` not passed → 10-min CI block contradicting single-shot framing; DA3.3 Direct-path silent commit-failure → state divergence; DA3.4 no end-to-end smoke test in Phase 4 ACs; DA3.5 USER_RESPONSE source unspecified. The 2 blockers and 1 major are fixed in round 3.

**/refine-plan Round-1 findings + dispositions:** Reviewer surfaced 7 defects + 3 meta-scan + 4 stale-reference items; DA surfaced 7 defect descriptions + 4 new bug categories. Refinement-round-1 outcomes:

- The D2+D3+M1+M2+DA1.1-1.3 entangled set was resolved by picking **Framing (a)**: keep `--no-monitor`, replace the "tracker edits are deterministic / no CI gates" framing with a principled "sync is interactive-by-design, user reviews PR and merges manually, CI runs against the merge commit on main post-merge" rationale. The canonical caller's structural shape (allow-list parsing, STATUS / CI_STATUS case-arms) is preserved; the `while :; do … continue` retry scaffold and the `<DISPATCH_FIX_CYCLE_AGENT_HERE>` block are explicitly stripped. The code-fix-agent-on-content-PR hazard from DA1.2 is avoided.
- D1: AC-P.9a rewritten as a negative assertion (plan-landing PR MUST NOT include `Closes #231/#233`; those belong to the implementation PR).
- D4: post-land verification discipline paragraph added to step 8; Hard constraint asserting `--auto` is absent; new AC-P.12 + AC-3.16 enforcing it.
- D5+DA1.6: prose cleanup (SPRINT_REPORT.md framed as secondary annotation site) + bash bug fix (conditional pathspec for missing SPRINT_REPORT.md in stash push, git add, and Direct path).
- D6+DA1.4+R1.S4: `tests/test-fix-issues-sync-smoke.sh` added with 4 isolated-recipe assertions, wired into `tests/run-all.sh` via explicit AC-4.11. Plan-quality "remaining concerns" section rewritten.
- D7+DA1.5: canary recipe restructured as a follow-up plan + orchestrator-emit-on-land instruction. NOT a hard AC; does not block `status: complete`.
- DA1.7: every bare `exit N` in the recipes is now paired with explicit orchestrator-prose STOP markers ("Orchestrator STOP: if you see ... above, STOP — do not execute subsequent blocks"), per a new plan-wide "Recipe exit semantics" section. The bash `exit N` calls are kept so the Bash tool's exit code propagates; the prose stops are kept so the orchestrator-level flow halts.
- DA1.8: Phase 5 WI 5.1 spec'd to handle verifier-polish-shifted-hash via a single conditional rebump-commit.
- DA1.9: WT_PATH timestamped (`/tmp/${PROJECT_NAME}-sync-${SYNC_TS}`) so concurrent sync runs do not collide; resume-mode adds a branch-mismatch check.
- DA1.10: WI 2.4 row-writer membership-check regex tightened to `(^|[^0-9A-Za-z_])#$N($|[^0-9])` so `bug#23` doesn't match `#23` and `#231` doesn't suppress a write for `#23`.
- R1.M3: Phase 5 prose reworded so hook-fail during the phase is treated as a real signal (per CLAUDE.md "feedback_hook_bypass").
- R1.S1: conformance-test line range corrected from "518-531" to "519-538" throughout (`tests/test-skill-conformance.sh`).
- R1.S2: justified-not-fix — the plan's claim that the `_ISSUES.md$` regex is at collect.py line 482 IS correct (verified). The reviewer's claim that it should be 481 is wrong: line 481 is the comment ("# issue_tracker: ends with _ISSUES.md"), line 482 is the `if re.search(...)` containing the regex.

**Convergence:** Refinement-round-1 fixed all 7 D-defects, all 3 M-defects, 3 of 4 S-defects (with R1.S2 justified-not-fix), and all 11 DA defects (DA1.11 was already clean). The Plan Quality narrative below was updated. A second refinement round, if commissioned, would focus on prose churn rather than structural rework.

**/refine-plan Round-2 findings + dispositions:** Round 2 surfaced 2 blockers + 1 framing-choice pivot + 3 majors + 5 minors (17 total: 8 reviewer + 9 devil's advocate, 3 cross-duplicates). Refinement-round-2 outcomes:

- **Framing pivot (Framing c/d).** Round-1's Framing-(a) choice (keep `--no-monitor`, justify with "sync is interactive") rested on a conflation: "sync is interactive" is true of all 4 no-auto canonical callers, not a differentiator. The reviewable hazard is the fix-cycle agent on a content PR (DA1.2 — sound). Dropping `--no-monitor` is independent of skipping fix-cycle. Round-2 pivot: drop `--no-monitor`, keep canonical monitor flow, and in `case "$CI_STATUS" in fail)` arm, `break` with a punt diagnostic — no fix-cycle agent dispatch. This matches `/quickfix`'s `CI_MAX_ATTEMPTS=0` posture (canonical caller variant skipping fix-cycle while preserving monitoring). Updated: plan-wide Design step 8 prose, Phase 3 WI 3.3 substep 8 + 10, AC-3.8 (second clause flipped from `≥1` to `=0`), AC-3.16 (whole-file `--auto` check; broken awk window fixed), Hard constraints, "What this plan does NOT do" prose, step 10 case-arm rewrite with CI-fail `break` branch.
- **DA2.1 (cross-bash variable scoping).** Round-1 plan assumed shell variables persist across Bash tool invocations; they don't. Fix: filesystem state directory `/tmp/sync-state-$SYNC_TS/` with one file per variable (`open_nums.txt`, `approved_list.txt`, `bootstrap_new.txt`, `stash_ts.txt`, `wt_path.txt`, `sync_branch.txt`, `user_response.txt`, `new_researched_count.txt`, plus a `proceed` sentinel). Added plan-wide Design subsection "Cross-block state persistence." Updated "Variable derivation" section to specify producer/consumer pattern with state-file reads/writes. Folds DA2.7 (STOP-marker enforcement — the `proceed` sentinel converts advisory STOP into a structural gate at the head of each block) and DA2.8 (USER_RESPONSE persistence — `user_response.txt`).
- **R2.1 (AC-3.16 awk blocker).** The awk window `^## Standalone Sync|^## Sync$` matched no real heading (actual: `## Sync (if \`sync\` is present)`), making the AC a trivial pass. Fixed by simplifying to whole-file `grep -cE -- '--auto'` returns 0 — strictly stronger.
- **R2.2 (smoke test invariant #1 under-specified).** Round-1's `^TRACKER$` check only validated the terminator. Body lines (`title: …`, `status: …`) must also be at column 0 for the bootstrapped YAML to parse. Strengthened WI 4.9 invariant #1 to assert all three column-0 checks; AC-4.11 updated to require ≥6 pass/fail lines (was 4).
- **DA2.3 (Results: format).** `tests/run-all.sh:run_suite()` parses `Results: N passed, M failed`. Without it the smoke test silently contributes 0 to counts. Added explicit Results-line requirement to WI 4.9, citing `tests/test-skill-content-hash.sh:135` as canonical convention; AC-4.11 adds a `tail -1` assertion.
- **DA2.4 (AC-P.9a regex).** Round-1's `^(Closes|Fixes) #(231|233)\b` anchored `^`, but real PR bodies use bulleted (`- **Closes #231**`) or inline forms. Loosened to `(close[sd]?|fixe[sd]?|resolve[sd]?) #(231|233)\b` (case-insensitive, no `^` anchor, verb forms).
- **DA2.5 (WT_PATH cleanup posture).** Documented as "leave worktree in place after successful land; `.landed` marker is the cleanup signal for future tools" in step 11. State-dir cleanup (`rm -rf "/tmp/sync-state-$SYNC_TS"`) happens at step 11 success and at abort-handler paths.
- **DA2.6 (canary stub artifact).** Created `docs/plans/FIX_ISSUES_SYNC_CANARY.md` stub (`status: draft`) with the canary recipe verbatim. The follow-up plan is a real artifact, not just intent.
- **DA2.7 / DA2.8.** Folded into DA2.1's state-directory mechanism (proceed sentinel + user_response.txt).
- **R2.3 (skills/land-pr/SKILL.md:320 doc drift).** Moot under the framing pivot — sync no longer uses `--no-monitor`, so the "None of the 5 callers use `--no-monitor`" invariant is preserved.
- **R2.4 / R2.5 / R2.6 (cosmetic narrow-window references).** Dropped narrow-window qualifiers in AC-P.12, AC-4.7, AC-3.16, WI 4.9 invariant #2 — the Standalone Sync window cannot be reliably extracted from SKILL.md headings, and whole-file checks are strictly stronger.
- **R2.7 (Round History).** Added row 5 to the table below.

**Remaining concerns:**
- The smoke test (`tests/test-fix-issues-sync-smoke.sh`) covers structural slips but not end-to-end runtime behavior — the canary recipe (now backed by a `status: draft` stub at `docs/plans/FIX_ISSUES_SYNC_CANARY.md`) is the intended end-to-end gate, gated on the follow-up plan being drafted and run.
- `monitored` is now reachable in sync's case-arm (canonical monitor flow runs). `merged` remains unreachable defensively (no `--auto`). The CI_STATUS case-arms now enumerate the FULL contract from `skills/land-pr/SKILL.md:162` (`pass|fail|pending|none|skipped|unknown|not-monitored`); if `/land-pr` introduces a new CI_STATUS value, sync's `*)` arm exits non-zero rather than misclassifying — fail-safe by construction.
- The cross-block state directory at `/tmp/sync-state-$SYNC_TS/` is cleaned up on successful land (step 11) and at every abort-path `exit N` (per the "Sync preamble — Abort-path cleanup mandate" prose). A SIGKILL or container teardown between blocks would still leak the directory; sync's next run uses a new `SYNC_TS` so there's no resume contamination, but `/tmp` may accrete state dirs on repeated hard crashes. **N3.R3 residual:** the abort-path cleanup is per-`exit-site` rather than a `trap EXIT` (because `trap` only fires within a single Bash tool invocation); the implementing agent must insert `rm -rf "/tmp/sync-state-$SYNC_TS"` immediately before every `exit N` clause in the Protected path. A future cleanup script can prune `/tmp/sync-state-*` directories older than N days as a defense-in-depth measure.
- **DA3.5 residual: `worktree_root` config ignored on resume.** Protected-path step 3 computes `WT_PATH="/tmp/${PROJECT_NAME}-${SLUG}"` directly rather than reading `worktree_root` from `.claude/zskills-config.json`. The `create-worktree.sh` dispatch in step 4 DOES honor `worktree_root` (so initial creation respects the config), but the step-3 resume check at `[ -d "$WT_PATH" ]` is hardcoded to `/tmp/`. If a project sets a non-default `worktree_root` (e.g., `/var/worktrees/`), resume into a prior sync's worktree silently fails to find it, falls through to create-worktree.sh, and either succeeds (if path doesn't collide) or fails on collision. Acceptable residual for v1 — sync's resume case is rare (requires a crashed prior sync with the same `SYNC_TS`, which is itself rare since `SYNC_TS` includes seconds). A future refinement can read `worktree_root` from config when computing the resume path. Documented here so a future debugger can correlate "resume silently failed" with non-default `worktree_root`.

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1 (/draft-plan) | 15 issues | 14 issues | 23 fix + 4 justified (4 cross-dups) |
| 2 (/draft-plan) | 8 issues | 9 issues | 14 fix (3 cross-dups, 4 blockers found+fixed) |
| 3 (/draft-plan) | 0 substantive + 2 polish | 5 substantive (2 blockers, 1 major, 2 minors) | 3 fix (blockers + major), 2 minor → 1 doc fix + 1 accepted residual |
| 4 (/refine-plan R1) | 7 defects + 3 meta + 4 stale-ref | 11 defects (1 blocker + 5 major + 5 minor) | 24 fix + 1 justified-not-fix (R1.S2 — reviewer evidence wrong) |
| 5 (/refine-plan R2) | 8 issues (R2.1-R2.7 + 1 framing pivot) | 9 issues (DA2.1-DA2.8 + 1 cross-dup) | 14 fix + 3 folded (DA2.7, DA2.8 → DA2.1; R2.3 → framing pivot); framing pivoted (a)→(c/d), DA2.1 architectural fix via filesystem state |
| 6 (/refine-plan R3) | 3 issues (N3.R1-N3.R3) | 5 issues (DA3.1-DA3.5) | 5 fix (N3.R1, N3.R2, DA3.1, DA3.3, DA3.4 + DA3.2 as Fix 5 empty-array round-trip) + 3 residuals documented (N3.R3 abort-cleanup, DA3.5 worktree_root); structural runtime bugs surfaced in Round-2 spec, all blockers fixed mechanically without design pivots |

### /refine-plan Round-3 findings + dispositions

Round 3 of /refine-plan focused on **runtime-blocking bugs in the Round-2 refinement** that the reviewer and devil's-advocate agents verified empirically against `skills/land-pr/SKILL.md`, `skills/land-pr/scripts/pr-monitor.sh`, and `skills/quickfix/SKILL.md`. All 4 of the verified blockers are mechanical bug fixes; no design pivots.

| Finding | Severity | Disposition | Location of fix |
|---------|----------|-------------|-----------------|
| N3.R1 / DA3.1 — SYNC_TS sequencing blocker (WI 2.1 state files write to `/tmp/sync-state-/`) | **BLOCKER** | **Fixed** | New "Sync preamble — SYNC_TS + state directory bootstrap" subsection added before "Protected path"; new WI 2.0 in Phase 2 inserts the preamble at the start of Phase 1a Sync; Protected-path step 3 no longer redefines `SYNC_TS` (defensive re-read from `sync_ts.txt` if needed); new AC-2.0 enforces preamble runs before WI 2.1's `gh issue list`; "Cross-block state persistence" prose updated to point at WI 2.0 instead of generic "step 0 (sync entry)" |
| N3.R2 — `break` in bare `case` (no enclosing loop) | **BLOCKER** | **Fixed** | Protected-path step 10 CI-fail arm: `break` replaced with `;;` (case-arm naturally terminates); inline comment added explaining why `break` was wrong; control flows through to step 11 cleanup |
| DA3.3 — CI_STATUS case-arm contract mismatch (`""\|pass\|skipped\|success` vs real `pass\|fail\|pending\|none\|skipped\|unknown\|not-monitored`) | **BLOCKER** | **Fixed** | Step 10 case-arms rewritten with full contract: success arm `""\|pass\|none\|skipped\|not-monitored`, **new** defer arm `pending\|unknown` (settle at pr-ready, don't close GH issues, exit clean), punt arm `fail` alone (NOT `fail\|failure` — `failure` is not a contract value), wildcard `*)` exits 1; inline comment cites `skills/land-pr/SKILL.md:162` and `skills/land-pr/scripts/pr-monitor.sh:120-125`; AC-3.8 expanded to enumerate the full contract |
| DA3.2 — False `/quickfix` precedent claim (claimed `CI_MAX_ATTEMPTS:-0`, actual `:-2`) | **BLOCKER (factual)** | **Fixed** | "Pattern alignment" paragraph rewritten as "No-precedent disclosure"; sync is acknowledged as the FIRST canonical-caller variant with no fix-cycle-agent dispatch; verified line refs cited (`skills/quickfix/SKILL.md:1076`, `~1159`); the principled justification (canonical fix-cycle agent template is for code+test, hazardous on content) stands on its own |
| DA3.4 — Empty-array round-trip (`printf '%s\n' "${EMPTY[@]}"` writes 1 byte, consumer `mapfile` creates 1-element-empty-string array, downstream `gh issue close ""`) | **BLOCKER** | **Fixed** | "Variable derivation" `APPROVED_LIST` block rewritten with producer guard (`[ "${#APPROVED_LIST[@]}" -gt 0 ]` → write content, else `: > file`) AND consumer empty-element filter (`for _X in ...; [ -n "$_X" ] && _APPROVED_FILTERED+=`); new AC-3.18 enforces both guards |
| N3.R3 — Abort-path state-dir cleanup inconsistency (claim "removes ... so /tmp does not accrete" but no abort-path `rm -rf` specified) | MINOR | **Documented as residual** | Sync preamble subsection adds explicit "Abort-path cleanup mandate" prose: every `exit N` clause must `rm -rf "/tmp/sync-state-$SYNC_TS"` first; Remaining concerns documents the SIGKILL-residual; no AC because the discipline is recipe-level (every abort site) |
| DA3.5 — `worktree_root` config ignored on resume (step 3 hardcodes `/tmp/`) | MINOR | **Documented as residual** | Remaining concerns added explaining the gap, why it's accepted for v1 (resume is rare; SYNC_TS includes seconds), and a future-refinement note for the `worktree_root` config-read on resume |

**Verification of all 4 blockers (post-refinement):**

- **Fix 1 (SYNC_TS sequencing):** `grep -nE 'SYNC_TS=' docs/plans/FIX_ISSUES_SYNC_HARDENING.md` returns the preamble assignment FIRST (in the "Sync preamble" subsection), with the Protected-path step 3 reference using a defensive `cat ... 2>/dev/null || echo "$SYNC_TS"` fallback rather than redefinition.
- **Fix 2 (case `break`):** `grep -nE '^[[:space:]]+break$' docs/plans/FIX_ISSUES_SYNC_HARDENING.md` returns zero hits inside the step-10 CI-fail arm context (verified by inspecting the case block).
- **Fix 3 (CI_STATUS contract):** Case-arms now spell `""|pass|none|skipped|not-monitored`, `pending|unknown`, `fail`, `*)` — verified by inspecting the step-10 block.
- **Fix 4 (precedent claim):** No "Pattern alignment" header remains; replaced with "No-precedent disclosure" naming `/quickfix`'s actual `:-2` posture.
- **Fix 5 (empty-array round-trip):** Producer guard `[ "${#APPROVED_LIST[@]}" -gt 0 ]` AND consumer filter loop both present in "Variable derivation".

**Convergence grep (post-refinement) — 4 historical hits preserved.** `grep -nEi 'deterministic|hygiene[^a-z]|single-shot|caller is special|content-only|tracker edits are' docs/plans/FIX_ISSUES_SYNC_HARDENING.md`: line 17 (hygiene-rejection, preserved verbatim per task constraint); line 579 (`content-only` — fix-cycle-agent rationale); lines in Plan Quality history sections (Round-3 disposition narrative + the `tracker edits are deterministic` quoted-string in the rejected-rationale paragraph). No new unprincipled framings introduced.
