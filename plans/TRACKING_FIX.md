---
title: Tracking Enforcement Fix
created: 2026-04-11
status: active
---

# Plan: Tracking Enforcement Fix

## Overview

The tracking enforcement system has several bugs that make it ineffective:

1. **Path mismatch** -- skills already migrated to `.zskills/tracking/` but the hook and tests still use `.claude/tracking`.
2. **Worktree blindness** -- hook uses `show-toplevel` which resolves to worktree root (no tracking dir there). The old design intentionally skipped worktrees, but the new design enforces in worktrees too via `git-common-dir`.
3. **Session guard fails for worktree agents** -- worktree agents get clean transcripts, so the transcript-based pipeline check never fires. Replaced with `.zskills-tracked` file written by the orchestrator.
4. **No pipeline scoping** -- Pipeline A's markers block Pipeline B's commits. Fixed by scoping marker checks to the pipeline ID from `.zskills-tracked`.
5. **No push enforcement** -- `git push` bypasses all tracking checks. Added.
6. **No config protection** -- `.zskills/config.json` can be overwritten by agents. Added write protection.
7. **Bash bug** -- `$(<"$FILE" 2>/dev/null)` returns empty; the `2>` breaks the `<` redirection form.
8. **`pipeline.active` replaced with scoped sentinel** -- `pipeline.active` is renamed to `pipeline.<skill>.<scope>` (e.g., `pipeline.research-and-go.rpg-build`). The mutex check in `/research-and-go` looks for `pipeline.research-and-go.*` specifically, not all markers. Staleness checks use `requires.*` mtime.

**Core design change:** The orchestrator writes `.zskills-tracked` in BOTH the worktree's LOCAL root AND the main repo root before dispatching agents. This file contains the pipeline ID (e.g., `run-plan.thermal-domain`). The hook reads it to associate the agent with a pipeline and scope marker checks to only matching markers. For sessions without `.zskills-tracked`, the transcript check is the fallback. For unrelated sessions (no `.zskills-tracked` AND no pipeline skill in transcript), enforcement is skipped -- parallel work is unblocked.

**Pipeline scoping uses suffix matching.** The pipeline ID must be the LAST dot-delimited segment(s) of the marker name. The hook checks `[[ "$base" != *".$PIPELINE_ID" ]]` (note the leading dot), not substring matching. This prevents false positives where pipeline ID "plan" matches "run-plan.thermal-domain".

**Step markers already include pipeline IDs.** Skills create step markers with the convention `step.<skill>.<tracking-id>.<stage>` (e.g., `step.run-plan.thermal-domain.implement`). The pipeline ID `run-plan.thermal-domain` is a suffix of that marker name, so suffix matching works correctly.

**Verification agent commits.** The orchestrator dispatches the verification agent to the worktree (without isolation). The verification agent runs the full test suite AND commits if verification passes. This means the verification agent's transcript contains the test command, satisfying the hook's test gate. The implementation agent does NOT commit.

**`.zskills-tracked` lifecycle:**
- Format: single-line string containing the pipeline ID (e.g., `run-plan.thermal-domain`)
- Added to `.gitignore` so it is never committed
- Written by the orchestrator before dispatching agents (in both worktree and main repo roots)
- Cleaned up by the orchestrator after pipeline completion

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 -- Hook Overhaul | 🟡 In Progress | fc8e9cf | Implemented + verified in worktree |
| 2 -- Test Suite | 🟡 In Progress | 60b1fa6 | 68 tests, 0 failures |
| 3 -- Skill Text Updates | pending | | Commit workflow + .zskills-tracked + scoped pipeline sentinel |

---

## Phase 1 -- Hook Overhaul

### Goal

Fix `hooks/block-unsafe-project.sh.template` to use the correct paths, resolve tracking from worktrees, replace the session guard with `.zskills-tracked` + transcript fallback, add pipeline scoping with suffix matching, add push enforcement (with code-files exemption), add config protection, fix the bash bug, and replace `pipeline.active` staleness with `requires.*` mtime. Also add `.zskills-tracked` to `.gitignore`.

### Files Modified

- `hooks/block-unsafe-project.sh.template` -- all hook changes below
- `.claude/hooks/block-unsafe-project.sh` -- sync installed copy (copy template, replace placeholders with values from the existing installed copy)
- `.gitignore` -- add `.zskills-tracked`

### Work Items

#### 1.1 -- Path migration: `.claude/tracking` -> `.zskills/tracking`

Replace ALL occurrences of `.claude/tracking` in the hook template. There are 4 occurrences:

- Line 33: tracking file protection regex
- Line 34: `block_with_reason` message
- Line 144: `TRACKING_DIR="$REPO_ROOT/.claude/tracking"`
- Line 263: `TRACKING_DIR="$REPO_ROOT/.claude/tracking"` (cherry-pick block)

**Old (line 33-34):**
```bash
if [[ "$INPUT" =~ rm[[:space:]].*-[a-zA-Z]*r[a-zA-Z]*.*\.claude/tracking ]]; then
  block_with_reason "BLOCKED: Cannot recursively delete tracking directory. To clear tracking state: ! bash scripts/clear-tracking.sh"
```

**New:**
```bash
if [[ "$INPUT" =~ rm[[:space:]].*-[a-zA-Z]*r[a-zA-Z]*.*\.zskills/tracking ]]; then
  block_with_reason "BLOCKED: Cannot recursively delete tracking directory. To clear tracking state: ! bash scripts/clear-tracking.sh"
```

**Old (line 144):**
```bash
TRACKING_DIR="$REPO_ROOT/.claude/tracking"
```

**New:**
```bash
TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"
```

(Same change at line 263.)

#### 1.2 -- Replace `show-toplevel` with `git-common-dir` for TRACKING_ROOT

The hook currently uses `show-toplevel` to find the tracking directory. In worktrees, this resolves to the worktree root (no tracking dir). Replace with `git-common-dir` which resolves to the main repo's `.git` parent in both main repo and worktrees.

The variable is `TRACKING_ROOT` (overridable for testing). `REPO_ROOT` stays as-is for other uses (package.json detection, git diff --cached, etc.).

**Old (lines 140-144, in `git commit` block):**
```bash
  # ─── Tracking enforcement (delegation + step verification) ───
  # Hook uses LOCAL repo root (show-toplevel), NOT git-common-dir.
  # In main repo: resolves to main repo (tracking dir exists → enforce).
  # In worktree: resolves to worktree root (tracking dir absent → skip).
  REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  TRACKING_DIR="$REPO_ROOT/.claude/tracking"
```

**New:**
```bash
  # ─── Tracking enforcement (delegation + step verification) ───
  # Hook uses git-common-dir to find tracking markers from worktrees.
  # TRACKING_ROOT resolves to main repo root in both main repo and worktrees.
  # Overridable via env var for testing.
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"
```

**Same change in the cherry-pick block (lines 261-263):**

**Old:**
```bash
  # ─── Tracking enforcement (delegation + step verification) ───
  REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  TRACKING_DIR="$REPO_ROOT/.claude/tracking"
```

**New:**
```bash
  # ─── Tracking enforcement (delegation + step verification) ───
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"
```

#### 1.3 -- Replace session-aware transcript guard with `.zskills-tracked` + transcript fallback

The current guard checks the transcript for pipeline skill names. This fails for worktree agents which get clean transcripts. Replace with a two-tier guard:

1. **Primary:** Check for `.zskills-tracked` file in the LOCAL repo root (`REPO_ROOT` from `show-toplevel`). This file is written by the orchestrator before dispatching agents. It contains the pipeline ID (single-line string).
2. **Fallback:** If no `.zskills-tracked`, check the transcript for pipeline skill names (covers the orchestrator on main). Pipeline ID is empty in this case (no scoping -- orchestrator sees ALL markers).
3. **Neither:** Skip enforcement (unrelated session -- parallel work unblocked).

The `.zskills-tracked` file also provides the pipeline ID for scoping (see 1.4).

**Old (lines 148-160, in `git commit` block):**
```bash
  # Session-aware guard (Change 6): only enforce tracking if THIS session has
  # actually invoked a pipeline skill. This lets parallel sessions on disjoint
  # files commit freely if they're not running their own tracked work.
  # Without this guard, session A's active pipeline blocks session B's
  # unrelated commits, which is unnecessarily restrictive.
  TRACKING_SESSION_HAS_PIPELINE=false
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK="${TRANSCRIPT_CONTENT:-$(cat "$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK=""
    for pipeline_skill in "/research-and-go" "/research-and-plan" "/run-plan" "/fix-issues" "/add-block" "/draft-plan" "/verify-changes"; do
      if [[ "$TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK" == *"$pipeline_skill"* ]]; then
        TRACKING_SESSION_HAS_PIPELINE=true
        break
      fi
    done
  fi

  # Skip if tracking dir doesn't exist (backward compatible)
  # OR if this session has not invoked any pipeline skill
  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then
```

**New:**
```bash
  # Pipeline association guard: determine if this session belongs to a tracked
  # pipeline. Two mechanisms:
  #
  # 1. .zskills-tracked file (primary) — written by orchestrator in the LOCAL
  #    repo root before dispatching agents. Contains the pipeline ID.
  #    Works in worktrees (agents get clean transcripts).
  #
  # 2. Transcript check (fallback) — for the orchestrator running on main,
  #    which has no .zskills-tracked but does have pipeline skills in transcript.
  #    PIPELINE_ID stays empty — orchestrator sees ALL markers (no scoping).
  #
  # Neither → unrelated session → skip enforcement → parallel work unblocked.
  REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  # Primary: .zskills-tracked file in LOCAL repo root
  if [ -f "$REPO_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$REPO_ROOT/.zskills-tracked" 2>/dev/null)
    PIPELINE_ID=$(echo "$PIPELINE_ID" | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Fallback: transcript check (orchestrator on main)
  # PIPELINE_ID stays empty — orchestrator is responsible for all its pipelines
  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK="${TRANSCRIPT_CONTENT:-$(cat "$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK=""
    for pipeline_skill in "/research-and-go" "/research-and-plan" "/run-plan" "/fix-issues" "/add-block" "/draft-plan" "/verify-changes"; do
      if [[ "$TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK" == *"$pipeline_skill"* ]]; then
        TRACKING_SESSION_HAS_PIPELINE=true
        break
      fi
    done
  fi

  # Also check for .zskills-tracked in MAIN repo root (orchestrator scoping)
  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -f "$TRACKING_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$TRACKING_ROOT/.zskills-tracked" 2>/dev/null)
    PIPELINE_ID=$(echo "$PIPELINE_ID" | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  # Skip if tracking dir doesn't exist (backward compatible)
  # OR if this session is not associated with any pipeline
  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then
```

**Same replacement in the cherry-pick block (lines 265-278).** The old code:

```bash
  # Session-aware guard (Change 6): only enforce if THIS session has
  # invoked a pipeline skill. Same logic as the git commit block above.
  TRACKING_SESSION_HAS_PIPELINE=false
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK="${TRANSCRIPT_CONTENT:-$(cat "$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK=""
    for pipeline_skill in "/research-and-go" "/research-and-plan" "/run-plan" "/fix-issues" "/add-block" "/draft-plan" "/verify-changes"; do
      if [[ "$TRANSCRIPT_CONTENT_FOR_PIPELINE_CHECK" == *"$pipeline_skill"* ]]; then
        TRACKING_SESSION_HAS_PIPELINE=true
        break
      fi
    done
  fi

  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then
```

Replace with the same `.zskills-tracked` + transcript fallback + main root fallback logic (identical to the commit block version above).

#### 1.4 -- Add pipeline scoping with suffix matching

When `PIPELINE_ID` is set (from `.zskills-tracked`), only check markers whose name ends with `.$PIPELINE_ID`. This uses suffix matching (not substring) to prevent false positives where pipeline ID "plan" would match "run-plan.thermal-domain".

When `PIPELINE_ID` is empty (transcript fallback -- orchestrator on main), check ALL markers (backward compatible -- orchestrator is responsible for all pipelines it spawns).

**Marker naming convention (already in use by skills):**
- `requires.verify-changes.$TRACKING_ID` -- e.g., `requires.verify-changes.thermal-domain`
- `step.run-plan.$TRACKING_ID.implement` -- e.g., `step.run-plan.thermal-domain.implement`
- `step.fix-issues.sprint.verify` -- pipeline ID is `fix-issues.sprint`
- `requires.verify-changes.final` -- cross-pipeline marker (orchestrator only)

**Suffix matching rule:** The pipeline ID is the last dot-delimited segment(s) of the marker name (before the stage suffix for step markers). For `requires.*` markers, the pipeline ID is the terminal segment(s). For `step.*` markers, the pipeline ID appears between the skill name and the stage name.

**Modify the delegation check loop.** Old:
```bash
      for req in "$TRACKING_DIR"/requires.*; do
        [ -f "$req" ] || continue
        base=$(basename "$req")
        fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
        if [ ! -f "$fulfilled" ]; then
          block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
        fi
      done
```

**New:**
```bash
      for req in "$TRACKING_DIR"/requires.*; do
        [ -f "$req" ] || continue
        base=$(basename "$req")
        # Pipeline scoping: if PIPELINE_ID is set, only check markers ending with .$PIPELINE_ID
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".$PIPELINE_ID" ]]; then
          continue
        fi
        fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
        if [ ! -f "$fulfilled" ]; then
          block_with_reason "BLOCKED: Required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
        fi
      done
```

**Same scoping for step enforcement.** The step markers use `step.<skill>.<tracking-id>.<stage>`, so the pipeline ID appears BEFORE the stage suffix. For step markers, strip the stage suffix first, then check if the remainder ends with the pipeline ID.

Old `step.*.implement` loop:
```bash
      for impl in "$TRACKING_DIR"/step.*.implement; do
        [ -f "$impl" ] || continue
        verify="${impl/\.implement/.verify}"
        if [ ! -f "$verify" ]; then
          session=$(basename "$impl" .implement)
          block_with_reason "BLOCKED: ${session#step.} has implementation but no verification. Run verification before landing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
```

**New:**
```bash
      for impl in "$TRACKING_DIR"/step.*.implement; do
        [ -f "$impl" ] || continue
        base=$(basename "$impl" .implement)
        # Pipeline scoping: strip stage suffix, check if remainder ends with pipeline ID
        # e.g., step.run-plan.thermal-domain → check if ends with .thermal-domain
        #   for PIPELINE_ID=run-plan.thermal-domain:
        #   base=step.run-plan.thermal-domain → contains .run-plan.thermal-domain → match
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".$PIPELINE_ID" ]]; then
          continue
        fi
        verify="${impl/\.implement/.verify}"
        if [ ! -f "$verify" ]; then
          block_with_reason "BLOCKED: ${base#step.} has implementation but no verification. Run verification before landing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
```

**Same for `step.*.verify` loop.** Old:
```bash
      for verif in "$TRACKING_DIR"/step.*.verify; do
        [ -f "$verif" ] || continue
        report="${verif/\.verify/.report}"
        if [ ! -f "$report" ]; then
          session=$(basename "$verif" .verify)
          block_with_reason "BLOCKED: ${session#step.} verified but no report written. Write report before landing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
```

**New:**
```bash
      for verif in "$TRACKING_DIR"/step.*.verify; do
        [ -f "$verif" ] || continue
        base=$(basename "$verif" .verify)
        # Pipeline scoping (same suffix match as implement loop)
        if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".$PIPELINE_ID" ]]; then
          continue
        fi
        report="${verif/\.verify/.report}"
        if [ ! -f "$report" ]; then
          block_with_reason "BLOCKED: ${base#step.} verified but no report written. Write report before landing. To clear: ! bash scripts/clear-tracking.sh"
        fi
      done
```

Apply the same scoping changes to all three loops in the cherry-pick block (they are duplicates of the commit block loops).

#### 1.5 -- Staleness check scoped to pipeline

When `PIPELINE_ID` is set, only check `requires.*` files matching this pipeline for staleness. When `PIPELINE_ID` is empty (orchestrator), check all `requires.*`.

**Old (lines 179-187, in `git commit` block):**
```bash
      # Staleness check: if pipeline.active is >8h old, warn but don't block
      PIPELINE_STALE=false
      if [ -f "$TRACKING_DIR/pipeline.active" ]; then
        STALE=$(find "$TRACKING_DIR/pipeline.active" -mmin +480 2>/dev/null)
        if [ -n "$STALE" ]; then
          echo "WARNING: Stale pipeline detected (>8h old). To clear: ! bash scripts/clear-tracking.sh" >&2
          PIPELINE_STALE=true
        fi
      fi
```

**New:**
```bash
      # Staleness check: if matching requires.* files are >8h old, warn but don't block
      PIPELINE_STALE=false
      if [ -n "$PIPELINE_ID" ]; then
        # Scoped: only check requires.* files ending with this pipeline's ID
        STALE_REQ=""
        for req in "$TRACKING_DIR"/requires.*; do
          [ -f "$req" ] || continue
          reqbase=$(basename "$req")
          if [[ "$reqbase" == *".$PIPELINE_ID" ]]; then
            stale_check=$(find "$req" -mmin +480 2>/dev/null)
            if [ -n "$stale_check" ]; then
              STALE_REQ="$req"
              break
            fi
          fi
        done
      else
        # Unscoped (orchestrator): check any requires.*
        STALE_REQ=$(find "$TRACKING_DIR" -name 'requires.*' -mmin +480 2>/dev/null | head -1)
      fi
      if [ -n "$STALE_REQ" ]; then
        echo "WARNING: Stale pipeline detected (requires.* >8h old). To clear: ! bash scripts/clear-tracking.sh" >&2
        PIPELINE_STALE=true
      fi
```

**Same change in the cherry-pick block (lines 280-288).**

#### 1.6 -- Add `git push` enforcement block with code-files check

Add a new top-level block (after the cherry-pick block, before the final `exit 0`) that gates `git push` with tracking checks. Include the same CODE_FILES exemption as the commit block -- content-only pushes are not blocked.

**Insert before `# No match — allow` (line 325):**

```bash
# Safety net: tracking enforcement on git push
# Push is the landing gate for PR mode — same tracking checks as commit/cherry-pick.
if [[ "$INPUT" =~ git[[:space:]]+push([[:space:]]|\") ]]; then
  TRACKING_ROOT="${TRACKING_ROOT:-$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)}"
  TRACKING_DIR="$TRACKING_ROOT/.zskills/tracking"

  # Pipeline association guard (same logic as commit/cherry-pick blocks)
  REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  PIPELINE_ID=""
  TRACKING_SESSION_HAS_PIPELINE=false

  if [ -f "$REPO_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$REPO_ROOT/.zskills-tracked" 2>/dev/null)
    PIPELINE_ID=$(echo "$PIPELINE_ID" | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  if ! $TRACKING_SESSION_HAS_PIPELINE; then
    TRANSCRIPT=$(extract_transcript)
    if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
      for pipeline_skill in "/research-and-go" "/research-and-plan" "/run-plan" "/fix-issues" "/add-block" "/draft-plan" "/verify-changes"; do
        if [[ "$TRANSCRIPT_CONTENT" == *"$pipeline_skill"* ]]; then
          TRACKING_SESSION_HAS_PIPELINE=true
          break
        fi
      done
    fi
  fi

  if ! $TRACKING_SESSION_HAS_PIPELINE && [ -f "$TRACKING_ROOT/.zskills-tracked" ]; then
    PIPELINE_ID=$(cat "$TRACKING_ROOT/.zskills-tracked" 2>/dev/null)
    PIPELINE_ID=$(echo "$PIPELINE_ID" | tr -d '[:space:]')
    if [ -n "$PIPELINE_ID" ]; then
      TRACKING_SESSION_HAS_PIPELINE=true
    fi
  fi

  if [ -d "$TRACKING_DIR" ] && $TRACKING_SESSION_HAS_PIPELINE; then

    # Check if any code files are in the push (compare local branch to remote tracking)
    CODE_FILES=""
    PUSH_DIFF=$(git diff --name-only @{u}..HEAD 2>/dev/null)
    if [ -n "$PUSH_DIFF" ]; then
      while IFS= read -r line; do
        if [[ "$line" =~ \.(js|jsx|mjs|cjs|ts|tsx|json|css|scss|html|vue|svelte|rs|py|go|rb|java|kt|swift|c|cc|cpp|h|hpp|sh|php)$ ]]; then
          CODE_FILES+="$line"$'\n'
        fi
      done <<< "$PUSH_DIFF"
    fi

    if [ -n "$CODE_FILES" ]; then

      # Staleness check: scoped to pipeline
      PIPELINE_STALE=false
      if [ -n "$PIPELINE_ID" ]; then
        STALE_REQ=""
        for req in "$TRACKING_DIR"/requires.*; do
          [ -f "$req" ] || continue
          reqbase=$(basename "$req")
          if [[ "$reqbase" == *".$PIPELINE_ID" ]]; then
            stale_check=$(find "$req" -mmin +480 2>/dev/null)
            if [ -n "$stale_check" ]; then
              STALE_REQ="$req"
              break
            fi
          fi
        done
      else
        STALE_REQ=$(find "$TRACKING_DIR" -name 'requires.*' -mmin +480 2>/dev/null | head -1)
      fi
      if [ -n "$STALE_REQ" ]; then
        echo "WARNING: Stale pipeline detected (requires.* >8h old). To clear: ! bash scripts/clear-tracking.sh" >&2
        PIPELINE_STALE=true
      fi

      if ! $PIPELINE_STALE; then
        # Delegation check
        for req in "$TRACKING_DIR"/requires.*; do
          [ -f "$req" ] || continue
          base=$(basename "$req")
          if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".$PIPELINE_ID" ]]; then
            continue
          fi
          fulfilled="${TRACKING_DIR}/${base/requires./fulfilled.}"
          if [ ! -f "$fulfilled" ]; then
            block_with_reason "BLOCKED: git push blocked — required skill invocation '${base#requires.}' not yet fulfilled. Invoke the required skill via the Skill tool. To clear stale tracking: ! bash scripts/clear-tracking.sh"
          fi
        done

        # Step enforcement
        for impl in "$TRACKING_DIR"/step.*.implement; do
          [ -f "$impl" ] || continue
          base=$(basename "$impl" .implement)
          if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".$PIPELINE_ID" ]]; then
            continue
          fi
          verify="${impl/\.implement/.verify}"
          if [ ! -f "$verify" ]; then
            block_with_reason "BLOCKED: git push blocked — ${base#step.} has implementation but no verification. Run verification before pushing. To clear: ! bash scripts/clear-tracking.sh"
          fi
        done

        for verif in "$TRACKING_DIR"/step.*.verify; do
          [ -f "$verif" ] || continue
          base=$(basename "$verif" .verify)
          if [ -n "$PIPELINE_ID" ] && [[ "$base" != *".$PIPELINE_ID" ]]; then
            continue
          fi
          report="${verif/\.verify/.report}"
          if [ ! -f "$report" ]; then
            block_with_reason "BLOCKED: git push blocked — ${base#step.} verified but no report written. Write report before pushing. To clear: ! bash scripts/clear-tracking.sh"
          fi
        done
      fi
    fi
  fi
fi
```

#### 1.7 -- Add `.zskills/config` write protection

Add a new block after the tracking file protection section (after line 39, before the session logging section). This blocks agent writes to `.zskills/config` while allowing reads.

**Insert after the `clear-tracking` block (after line 39):**

```bash
# ─── Config file protection ───
# .zskills/config.json is user-managed. Block agent writes, allow reads.
if [[ "$INPUT" =~ ((\>|tee|sed[[:space:]]+-i|cp|mv)[[:space:]].*\.zskills/config|echo[[:space:]].*\.zskills/config) ]]; then
  block_with_reason "BLOCKED: .zskills/config.json is user-managed. Do not modify it directly. Ask the user to update the config."
fi
```

#### 1.8 -- Fix bash bug (`$(<` -> `cat`)

Replace all `$(<"$FILE" 2>/dev/null)` patterns with `$(cat "$FILE" 2>/dev/null)`.

There are 3 occurrences at lines 103, 131, and 254:

**Line 103 -- old:**
```bash
      TRANSCRIPT_CONTENT=$(<"$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
```
**New:**
```bash
      TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
```

**Line 131 -- old:**
```bash
        TRANSCRIPT_CONTENT="${TRANSCRIPT_CONTENT:-$(<"$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT=""
```
**New:**
```bash
        TRANSCRIPT_CONTENT="${TRANSCRIPT_CONTENT:-$(cat "$TRANSCRIPT" 2>/dev/null)}" || TRANSCRIPT_CONTENT=""
```

**Line 254 -- old:**
```bash
      TRANSCRIPT_CONTENT=$(<"$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
```
**New:**
```bash
      TRANSCRIPT_CONTENT=$(cat "$TRANSCRIPT" 2>/dev/null) || TRANSCRIPT_CONTENT=""
```

**Note:** The `$(<"$REPO_ROOT/package.json")` at lines 85 and 237 does NOT have `2>/dev/null` so it works correctly -- leave those alone.

#### 1.9 -- Add `.zskills-tracked` to `.gitignore`

**File:** `.gitignore`

Add the following line to the `.gitignore` file (near the existing `.zskills/tracking/` entry):

```
.zskills-tracked
```

#### 1.10 -- Sync installed copy

After all changes to the template, copy to `.claude/hooks/block-unsafe-project.sh` and apply the same placeholder replacements that the existing installed copy has. Read the installed copy first to determine what values the placeholders were replaced with (check for `UNIT_TEST_CMD`, `FULL_TEST_CMD`, `UI_FILE_PATTERNS`).

```bash
cp hooks/block-unsafe-project.sh.template .claude/hooks/block-unsafe-project.sh
# Apply same sed replacements as install process
```

### Verification

After all changes:
1. Run `bash tests/test-hooks.sh > .test-results.txt 2>&1` -- existing tests should still pass (they test the generic hook, not yet the project hook tracking changes)
2. Manually verify the hook with a quick smoke test:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf .zskills/tracking"}}' | bash hooks/block-unsafe-project.sh.template
   # Should output deny JSON
   ```

---

## Phase 2 -- Test Suite

### Goal

Expand `tests/test-hooks.sh` to cover all new enforcement paths: `.zskills/tracking` paths, `TRACKING_ROOT` injection, `.zskills-tracked` pipeline association, pipeline scoping with suffix matching, `git push` enforcement (with code-files exemption), `.zskills/config` protection, and scoped `requires.*` mtime staleness.

### Dependencies

Phase 1 must be complete (tests exercise the new hook behavior).

### Files Modified

- `tests/test-hooks.sh` -- all changes below

### Work Items

#### 2.1 -- Migrate existing tracking paths

Replace ALL occurrences of `.claude/tracking` with `.zskills/tracking` in the test file. Occurrences:

- Line 149: `mkdir -p "$TEST_TMPDIR/.claude/tracking"`
- Lines 203-209: tracking protection test paths
- Lines 227-238: delegation test paths
- Lines 244: delegation cherry-pick test
- Lines 252-279: step enforcement test paths
- Lines 292-296: staleness test paths
- Lines 305: backward compat test (rmdir)
- Lines 312-313: content-only test paths
- Lines 335: git commit-tree test
- Lines 347-351: CODE_FILES extension test paths
- Lines 357: content-only .md test path

All instances of `.claude/tracking` in test file -> `.zskills/tracking`.

#### 2.2 -- Update `setup_project_test` helper

**Old:**
```bash
setup_project_test() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  mkdir -p "$TEST_TMPDIR/.claude/tracking"

  # Copy and configure the hook template
  cp "$PROJECT_HOOK" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json with test script
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"

  # Create mock transcript with test command AND a pipeline skill invocation
  # (the latter satisfies the Change 6 session-aware guard so tracking
  # enforcement actually fires when expected)
  printf '/run-plan plans/foo.md\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"

  # Initialize git repo (needed for git diff --cached, etc.)
  (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null)
}
```

**New:**
```bash
setup_project_test() {
  TEST_TMPDIR=$(mktemp -d)
  mkdir -p "$TEST_TMPDIR/.claude/hooks"
  mkdir -p "$TEST_TMPDIR/.zskills/tracking"

  # Copy and configure the hook template
  cp "$PROJECT_HOOK" "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UNIT_TEST_CMD}}|npm test|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{FULL_TEST_CMD}}|npm run test:all|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"
  sed -i 's|{{UI_FILE_PATTERNS}}|src/ui/|g' "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh"

  # Create mock package.json with test script
  printf '{"scripts":{"test":"vitest","test:all":"vitest run"}}\n' > "$TEST_TMPDIR/package.json"

  # Create mock transcript with test command AND a pipeline skill invocation
  # (the latter satisfies the transcript fallback guard so tracking
  # enforcement fires when expected for orchestrator-on-main tests)
  printf '/run-plan plans/foo.md\nnpm run test:all\n' > "$TEST_TMPDIR/.transcript"

  # Initialize git repo (needed for git diff --cached, git-common-dir, etc.)
  (cd "$TEST_TMPDIR" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null)
}
```

#### 2.3 -- Add `TRACKING_ROOT` and `cd` to test helpers

The hook now uses `git-common-dir` which requires git context. Tests must `cd` into the test repo AND inject `TRACKING_ROOT`.

**Old `expect_project_deny`:**
```bash
expect_project_deny() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" bash "$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh" 2>/dev/null)
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "$cmd → denied (expected)"
  else
    fail "$cmd → allowed (expected deny)"
  fi
}
```

**New:**
```bash
expect_project_deny() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" TRACKING_ROOT="$TEST_TMPDIR" bash -c "cd '$TEST_TMPDIR' && bash '$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ "$result" == *"permissionDecision"*"deny"* ]]; then
    pass "$cmd → denied (expected)"
  else
    fail "$cmd → allowed (expected deny)"
  fi
}
```

**Same change to `expect_project_allow`:**
```bash
expect_project_allow() {
  local cmd="$1"
  local json="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$cmd\"},\"transcript_path\":\"$TEST_TMPDIR/.transcript\"}"
  local result
  result=$(echo "$json" | REPO_ROOT="$TEST_TMPDIR" TRACKING_ROOT="$TEST_TMPDIR" bash -c "cd '$TEST_TMPDIR' && bash '$TEST_TMPDIR/.claude/hooks/block-unsafe-project.sh'" 2>/dev/null)
  if [[ -z "$result" ]] || [[ "$result" != *"deny"* ]]; then
    pass "$cmd → allowed (expected)"
  else
    fail "$cmd → denied (expected allow)"
  fi
}
```

#### 2.4 -- Add `.zskills-tracked` pipeline association tests

Add a new test section after the "backward compatibility" section:

```bash
echo ""
echo "=== Project hook: .zskills-tracked pipeline association ==="

# Test: .zskills-tracked file associates agent with pipeline
setup_project_test
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Remove transcript so ONLY .zskills-tracked provides the association
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_deny "git commit -m test"
teardown_project_test

# Test: .zskills-tracked with fulfilled requirement allows commit
setup_project_test
printf 'run-plan.thermal-domain\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: no .zskills-tracked AND no pipeline in transcript → skip enforcement
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript has test command but NO pipeline skill
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test
```

#### 2.5 -- Add pipeline scoping tests (suffix matching)

```bash
echo ""
echo "=== Project hook: pipeline scoping (suffix matching) ==="

# Test: Pipeline A's markers don't block Pipeline B
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
# Create unfulfilled requirement for pipeline A (different pipeline)
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Same pipeline's markers DO block
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Transcript fallback (no .zskills-tracked) checks ALL markers
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
# Transcript has pipeline skill → fallback fires, checks all markers
expect_project_deny "git commit -m test"
teardown_project_test

# Test: Step scoping — pipeline B's impl marker doesn't block pipeline A
setup_project_test
printf 'run-plan.pipeline-A\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.pipeline-B.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git commit -m test"
teardown_project_test

# Test: Suffix matching prevents false positives (ID "plan" does NOT match "run-plan.thermal-domain")
setup_project_test
printf 'plan\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.thermal-domain"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
# "plan" does NOT end ".run-plan.thermal-domain" → marker skipped → allowed
expect_project_allow "git commit -m test"
teardown_project_test
```

#### 2.6 -- Add `git push` enforcement tests

```bash
echo ""
echo "=== Project hook: push enforcement ==="

# Test: git push blocked by unfulfilled requirement
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.fix-issues.sprint"
# Create a remote tracking branch so git diff @{u}..HEAD works
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js && git commit -q -m "code" && git branch --set-upstream-to=HEAD 2>/dev/null)
expect_project_deny "git push origin main"
teardown_project_test

# Test: git push allowed when requirement fulfilled
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.fix-issues.sprint"
touch "$TEST_TMPDIR/.zskills/tracking/fulfilled.verify-changes.fix-issues.sprint"
expect_project_allow "git push origin main"
teardown_project_test

# Test: git push blocked by step without verification
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/step.run-plan.thermal-domain.implement"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js && git commit -q -m "code" && git branch --set-upstream-to=HEAD 2>/dev/null)
expect_project_deny "git push origin main"
teardown_project_test

# Test: git push with pipeline scoping
setup_project_test
printf 'run-plan.pipeline-A\n' > "$TEST_TMPDIR/.zskills-tracked"
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
expect_project_allow "git push origin main"
teardown_project_test

# Test: content-only push allowed despite unfulfilled requirements
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.fix-issues.sprint"
# Only markdown files in the push diff — no code files
(cd "$TEST_TMPDIR" && echo "# readme" > README.md && git add README.md && git commit -q -m "docs" && git branch --set-upstream-to=HEAD 2>/dev/null)
expect_project_allow "git push origin main"
teardown_project_test
```

#### 2.7 -- Add `.zskills/config` protection tests

```bash
echo ""
echo "=== Project hook: config file protection ==="

setup_project_test

# Block writes
expect_project_deny "echo '{}' > .zskills/config.json"
expect_project_deny "tee .zskills/config.json"
expect_project_deny "sed -i 's/a/b/' .zskills/config.json"
expect_project_deny "cp template.json .zskills/config.json"
expect_project_deny "mv tmp.json .zskills/config.json"

# Allow reads
expect_project_allow "cat .zskills/config.json"
expect_project_allow "grep debug .zskills/config.json"

teardown_project_test
```

#### 2.8 -- Add staleness test using scoped `requires.*` mtime

Replace the existing staleness test (which uses `pipeline.active`):

**Old:**
```bash
echo ""
echo "=== Project hook: staleness protection ==="

# Test: stale pipeline.active (>8h) allows commit despite requires.*
setup_project_test
touch "$TEST_TMPDIR/.claude/tracking/requires.verify-changes"
touch "$TEST_TMPDIR/.claude/tracking/pipeline.active"
# Make pipeline.active look old (>8h = 480min)
touch -t 202501010000 "$TEST_TMPDIR/.claude/tracking/pipeline.active"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test
```

**New:**
```bash
echo ""
echo "=== Project hook: staleness protection ==="

# Test: stale requires.* (>8h) allows commit despite unfulfilled requirement
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.fix-issues.sprint"
# Make requires file look old (>8h = 480min)
touch -t 202501010000 "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.fix-issues.sprint"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_allow "git commit -m test"
teardown_project_test

# Test: fresh requires.* still blocks
setup_project_test
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.fix-issues.sprint"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
expect_project_deny "git commit -m test"
teardown_project_test

# Test: scoped staleness — stale Pipeline A doesn't disable fresh Pipeline B
setup_project_test
printf 'run-plan.pipeline-B\n' > "$TEST_TMPDIR/.zskills-tracked"
# Pipeline A's requirement is stale
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
touch -t 202501010000 "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-A"
# Pipeline B's requirement is fresh
touch "$TEST_TMPDIR/.zskills/tracking/requires.verify-changes.run-plan.pipeline-B"
(cd "$TEST_TMPDIR" && echo "var x=1;" > app.js && git add app.js)
rm -f "$TEST_TMPDIR/.transcript"
printf 'npm run test:all\n' > "$TEST_TMPDIR/.transcript"
# Pipeline B is fresh and unfulfilled → still blocks
expect_project_deny "git commit -m test"
teardown_project_test
```

#### 2.9 -- Update tracking file protection tests

**Old:**
```bash
expect_project_deny "rm -rf .claude/tracking"
expect_project_deny "rm -r .claude/tracking"
expect_project_deny "rm -fr .claude/tracking"

expect_project_allow "rm .claude/tracking/requires.foo"
expect_project_allow "rm -f .claude/tracking/pipeline.active"
```

**New:**
```bash
expect_project_deny "rm -rf .zskills/tracking"
expect_project_deny "rm -r .zskills/tracking"
expect_project_deny "rm -fr .zskills/tracking"

expect_project_allow "rm .zskills/tracking/requires.foo"
expect_project_allow "rm -f .zskills/tracking/requires.old"
```

### Verification

Run: `bash tests/test-hooks.sh > .test-results.txt 2>&1`

All tests must pass. Expected test count increase: ~30-35 new tests (from ~45 to ~75-80).

---

## Phase 3 -- Skill Text Updates

### Goal

Update skill files to reflect the new enforcement model: remove "commit freely in worktrees" language, add verification-first commit workflow, add `.zskills-tracked` creation in orchestrator dispatch (both worktree and main repo roots), replace `pipeline.active` with scoped `pipeline.<skill>.<scope>` sentinel, add `.zskills-tracked` cleanup after pipeline completion, update `/do` skill, add `.zskills-tracked` dispatch for `/add-block` and `/add-example`, and update documentation.

### Dependencies

Phase 1 must be complete (skills reference the new guard mechanism).

### Files Modified

1. `skills/run-plan/SKILL.md` -- commit discipline + `.zskills-tracked` + cleanup
2. `skills/fix-issues/SKILL.md` -- commit discipline + scoped pipeline sentinel + `.zskills-tracked` + cleanup
3. `skills/research-and-go/SKILL.md` -- scoped pipeline sentinel + `.zskills-tracked` + cleanup
4. `skills/research-and-plan/SKILL.md` -- update pipeline sentinel references
5. `skills/do/SKILL.md` -- remove "commit freely" language
6. `block-diagram/add-block/SKILL.md` -- add `.zskills-tracked` dispatch
7. `block-diagram/add-example/SKILL.md` -- add `.zskills-tracked` dispatch
8. `CLAUDE_TEMPLATE.md` -- update tracking enforcement docs
9. `.claude/skills/run-plan/SKILL.md` -- sync installed copy
10. `.claude/skills/fix-issues/SKILL.md` -- sync installed copy
11. `.claude/skills/research-and-go/SKILL.md` -- sync installed copy
12. `.claude/skills/research-and-plan/SKILL.md` -- sync installed copy
13. `.claude/skills/do/SKILL.md` -- sync installed copy

### Work Items

#### 3.1 -- `/run-plan`: Remove "commit freely" and add verification-first workflow

**File:** `skills/run-plan/SKILL.md`

**Old (line 513):**
```
   - Agents commit freely in worktrees — that's the point of isolation
```

**New:**
```
   - The implementation agent does NOT commit. The verification agent runs the full test suite and commits if verification passes. This ensures the hook's test gate is satisfied (the committing agent's transcript contains the test command).
```

#### 3.2 -- `/run-plan`: Add `.zskills-tracked` creation in worktree dispatch

**File:** `skills/run-plan/SKILL.md`

Find the "Commit discipline" section at line 509 (item 5 in Phase 1 step list). After the new verification-first text from 3.1, add a new bullet:

**Insert after the modified line 513 (new verification-first text):**
```
   - **Before dispatching any worktree agent**, the orchestrator writes the pipeline ID to BOTH the worktree and the main repo root:
     ```bash
     printf '%s\n' "run-plan.$TRACKING_ID" > "<worktree-path>/.zskills-tracked"
     printf '%s\n' "run-plan.$TRACKING_ID" > "$MAIN_ROOT/.zskills-tracked"
     ```
     Where `$TRACKING_ID` is the plan slug (e.g., `thermal-domain`). This file associates agents with this pipeline for hook enforcement.
```

#### 3.3 -- `/run-plan`: Add `.zskills-tracked` cleanup after pipeline completion

**File:** `skills/run-plan/SKILL.md`

Find the landing section (Phase 4, around line 1170). After the `.landed` marker is written, add cleanup:

**Insert after the `.landed` marker write (around line 1180, after `fulfilled.run-plan.$TRACKING_ID`):**
```
   Remove the `.zskills-tracked` files to avoid associating future sessions with a dead pipeline:
   ```bash
   rm -f "<worktree-path>/.zskills-tracked"
   rm -f "$MAIN_ROOT/.zskills-tracked"
   ```
```

#### 3.4 -- `/fix-issues`: Remove "commit freely" (two locations)

**File:** `skills/fix-issues/SKILL.md`

**Old (lines 681-682):**
```
Agents commit freely in worktrees — that's the point of isolation. Worktree
commits are safe and expected. The approval gate is landing to main (Phase 6).
```

**New:**
```
The implementation agent does NOT commit. The verification agent runs the full
test suite and commits if verification passes. This ensures the hook's test
gate is satisfied. The approval gate is landing to main (Phase 6).
```

**Old (lines 1085-1086):**
```
- **Agents commit freely in worktrees** — that's the point of isolation.
  Worktree commits are safe and expected.
```

**New:**
```
- **The verification agent commits after passing tests** — the implementation
  agent does not commit. This satisfies the hook's test gate.
```

#### 3.5 -- `/fix-issues`: Replace `pipeline.active` with scoped `pipeline.fix-issues.<scope>`

**File:** `skills/fix-issues/SKILL.md`

**Old (lines 377-384):**
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking"
if [ ! -f "$MAIN_ROOT/.zskills/tracking/pipeline.active" ]; then
  printf 'skill: fix-issues\nmode: sprint\ncount: %s\nfocus: %s\nstartedAt: %s\n' \
    "$N" "${FOCUS:-default}" "$(TZ=America/New_York date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/pipeline.active"
fi
# Lock down the verification requirement EARLY (was Phase 4, now entry)
```

**New:**
```bash
MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
mkdir -p "$MAIN_ROOT/.zskills/tracking"
if [ ! -f "$MAIN_ROOT/.zskills/tracking/pipeline.fix-issues.sprint" ]; then
  printf 'skill: fix-issues\nmode: sprint\ncount: %s\nfocus: %s\nstartedAt: %s\n' \
    "$N" "${FOCUS:-default}" "$(TZ=America/New_York date -Iseconds)" \
    > "$MAIN_ROOT/.zskills/tracking/pipeline.fix-issues.sprint"
fi
# Lock down the verification requirement EARLY (was Phase 4, now entry)
```

#### 3.6 -- `/fix-issues`: Add `.zskills-tracked` creation in agent dispatch

**File:** `skills/fix-issues/SKILL.md`

Find the Phase 3 agent dispatch section. The dispatch logic starts around line 650 (Phase 3 -- Execute). The worktree creation is described around line 670. Add `.zskills-tracked` creation after worktree creation, before agent dispatch.

**Insert before the agent dispatch instructions in Phase 3 (after worktree creation, ~line 675):**

```
Before dispatching each fix agent to its worktree, the orchestrator writes the
pipeline ID to BOTH the worktree and the main repo root:

```bash
printf '%s\n' "fix-issues.sprint" > "<worktree-path>/.zskills-tracked"
printf '%s\n' "fix-issues.sprint" > "$MAIN_ROOT/.zskills-tracked"
```

This associates the agent with this pipeline for hook enforcement.
```

#### 3.7 -- `/fix-issues`: Add `.zskills-tracked` cleanup after sprint completion

**File:** `skills/fix-issues/SKILL.md`

Find Phase 6 (Landing, around line 930). After landing is complete, add cleanup:

**Insert after the landing/report section:**
```
After the sprint completes (whether all issues landed or the sprint ended),
clean up the pipeline association files:

```bash
rm -f "$MAIN_ROOT/.zskills-tracked"
rm -f "$MAIN_ROOT/.zskills/tracking/pipeline.fix-issues.sprint"
```

Also remove `.zskills-tracked` from each worktree that was used.
```

#### 3.8 -- `/research-and-go`: Replace `pipeline.active` with scoped `pipeline.research-and-go.<scope>`

**File:** `skills/research-and-go/SKILL.md`

**Old (lines 45-56):**
```
**Check for existing pipeline:** If `$MAIN_ROOT/.zskills/tracking/pipeline.active`
exists, STOP. Read the file and report its contents — another pipeline is already
in progress. Do not proceed unless this is a deliberate re-run (see Re-run
Handling below).

**Create the sentinel:**

```bash
printf 'skill=research-and-go\ngoal=%s\nstartedAt=%s\n' "$DESCRIPTION" "$(date -Iseconds)" > "$MAIN_ROOT/.zskills/tracking/pipeline.active"
```

Where `$DESCRIPTION` is the broad goal passed to this command.
```

**New:**
```
**Check for existing research-and-go pipeline:** If any
`$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.*` files exist, STOP.
Read the file and report its contents — another research-and-go pipeline is
already in progress. Do not proceed unless this is a deliberate re-run (see
Re-run Handling below).

**Create the scoped sentinel:**

```bash
SCOPE=$(echo "$DESCRIPTION" | tr '[:upper:] ' '[:lower:]-' | sed 's/[^a-z0-9-]//g' | cut -c1-30)
printf 'skill=research-and-go\ngoal=%s\nstartedAt=%s\n' "$DESCRIPTION" "$(date -Iseconds)" > "$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.$SCOPE"
```

Where `$DESCRIPTION` is the broad goal passed to this command and `$SCOPE` is a
slugified version for scoping.

**Write `.zskills-tracked` in the main repo root:**

```bash
printf '%s\n' "research-and-go.$SCOPE" > "$MAIN_ROOT/.zskills-tracked"
```
```

Also update the Re-run Handling section (lines 70-79):

**Old:**
```
If `pipeline.active` already exists and this is a deliberate re-run of the same
goal:

1. Read the existing `pipeline.active` to confirm the goal matches.
2. Check which `requires.*` files already exist in `$MAIN_ROOT/.zskills/tracking/`.
3. For each existing requirement, check if a corresponding `completed.*` file
   exists. Only create new requirement files for unfulfilled requirements.
4. Overwrite `pipeline.active` with a fresh timestamp.
```

**New:**
```
If `pipeline.research-and-go.*` already exists and this is a deliberate re-run
of the same goal:

1. Read the existing `pipeline.research-and-go.*` to confirm the goal matches.
2. Check which `requires.*` files already exist in `$MAIN_ROOT/.zskills/tracking/`.
3. For each existing requirement, check if a corresponding `fulfilled.*` file
   exists. Only create new requirement files for unfulfilled requirements.
4. Touch existing `requires.*` files to refresh their mtime (prevents staleness
   false positives).
5. Overwrite the `pipeline.research-and-go.*` sentinel with a fresh timestamp.
```

#### 3.9 -- `/research-and-go`: Add `.zskills-tracked` cleanup after pipeline completion

**File:** `skills/research-and-go/SKILL.md`

Find the final verification section (the cross-branch verification at the end of the skill). After the final verification completes, add cleanup:

**Insert after final verification:**
```
After the pipeline completes, clean up:

```bash
rm -f "$MAIN_ROOT/.zskills-tracked"
rm -f "$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.$SCOPE"
```
```

#### 3.10 -- `/research-and-plan`: Update `pipeline.active` references to scoped sentinel

**File:** `skills/research-and-plan/SKILL.md`

**Old (lines 293-295):**
```
If `$MAIN_ROOT/.zskills/tracking/pipeline.active` does **not** exist, this is a
standalone invocation. Create requirement files for each phase that delegates to
`/run-plan`:
```

**New:**
```
If no `$MAIN_ROOT/.zskills/tracking/pipeline.research-and-go.*` files exist,
this is a standalone invocation. Create requirement files for each phase that
delegates to `/run-plan`:
```

**Old (lines 309-310):**
```
If `pipeline.active` **does** exist, `/research-and-go` already created the
requirement files in its Step 1b — do not create duplicates.
```

**New:**
```
If `pipeline.research-and-go.*` files exist, `/research-and-go` already created
the requirement files in its Step 1b — do not create duplicates.
```

#### 3.11 -- `/do`: Remove "commit freely" language

**File:** `skills/do/SKILL.md`

**Old (line 240):**
```
   - **In worktree:** commit freely (that's the point of isolation).
```

**New:**
```
   - **In worktree:** the verification agent commits after tests pass.
```

#### 3.12 -- `/add-block`: Add `.zskills-tracked` dispatch

**File:** `block-diagram/add-block/SKILL.md`

Find the tracking setup section (around line 50, where `requires.add-example.${BLOCK_NAME}` and `requires.verify-changes.${BLOCK_NAME}` are created). After the tracking markers are created, add `.zskills-tracked` creation for when the skill dispatches agents to worktrees.

**Insert after the tracking marker creation (after line 67, after "will be blocked until the corresponding `fulfilled.*` markers exist"):**

```
Before dispatching any agent to a worktree, write the pipeline ID:

```bash
printf '%s\n' "add-block.${BLOCK_NAME}" > "<worktree-path>/.zskills-tracked"
printf '%s\n' "add-block.${BLOCK_NAME}" > "$MAIN_ROOT/.zskills-tracked"
```
```

#### 3.13 -- `/add-example`: Add `.zskills-tracked` dispatch

**File:** `block-diagram/add-example/SKILL.md`

Find the tracking setup section (around line 31, where `fulfilled.add-example.${NAME}` is created). Add `.zskills-tracked` creation for worktree dispatch.

**Insert after the fulfilled marker creation:**

```
Before dispatching any agent to a worktree, write the pipeline ID:

```bash
printf '%s\n' "add-example.${NAME}" > "<worktree-path>/.zskills-tracked"
printf '%s\n' "add-example.${NAME}" > "$MAIN_ROOT/.zskills-tracked"
```
```

#### 3.14 -- Update `CLAUDE_TEMPLATE.md`

**File:** `CLAUDE_TEMPLATE.md`

**Old (line 141):**
```
Tracking file enforcement is active when `.zskills/tracking/` exists. Skills create tracking files during pipeline execution; hooks check them before allowing commits. See the tracking enforcement section in `block-unsafe-project.sh` for details. The `clear-tracking.sh` script in `scripts/` lets the user manually clear stale tracking state -- agents are blocked from running it directly.
```

**New:**
```
Tracking file enforcement is active when `.zskills/tracking/` exists and the session is associated with a pipeline (via `.zskills-tracked` file or transcript). Skills create tracking files during pipeline execution; hooks check them before allowing `git commit`, `git cherry-pick`, and `git push`. Pipeline scoping (suffix matching on pipeline ID) ensures one pipeline's markers don't block another. The orchestrator writes `.zskills-tracked` (single-line pipeline ID) in both the worktree and main repo roots before dispatching agents, and removes it after pipeline completion. The `clear-tracking.sh` script in `scripts/` lets the user manually clear stale tracking state -- agents are blocked from running it directly.
```

#### 3.15 -- Sync ALL installed skill copies

After editing source skills, sync ALL installed copies that exist:

```bash
cp skills/run-plan/SKILL.md .claude/skills/run-plan/SKILL.md
cp skills/fix-issues/SKILL.md .claude/skills/fix-issues/SKILL.md
cp skills/research-and-go/SKILL.md .claude/skills/research-and-go/SKILL.md
cp skills/research-and-plan/SKILL.md .claude/skills/research-and-plan/SKILL.md
cp skills/do/SKILL.md .claude/skills/do/SKILL.md
```

### Verification

1. `grep -r "commit freely" skills/ block-diagram/` -- should return no results
2. `grep -r "commit freely" .claude/skills/` -- should return no results
3. `grep 'pipeline\.active' skills/research-and-go/SKILL.md skills/fix-issues/SKILL.md skills/research-and-plan/SKILL.md` -- should return no results
4. `grep 'pipeline\.active' .claude/skills/research-and-go/SKILL.md .claude/skills/fix-issues/SKILL.md .claude/skills/research-and-plan/SKILL.md` -- should return no results
5. `grep "zskills-tracked" skills/run-plan/SKILL.md skills/fix-issues/SKILL.md skills/research-and-go/SKILL.md block-diagram/add-block/SKILL.md block-diagram/add-example/SKILL.md` -- should return results for all 5 files
6. `grep "pipeline\.research-and-go\." skills/research-and-go/SKILL.md` -- should return results (scoped sentinel)
7. `grep "pipeline\.fix-issues\." skills/fix-issues/SKILL.md` -- should return results (scoped sentinel)
8. Run full test suite: `bash tests/test-hooks.sh > .test-results.txt 2>&1` -- all tests pass
