---
title: /quickfix Skill — Low-Ceremony Branch+Commit+PR from Main
created: 2026-04-19
status: active
---

# Plan: /quickfix Skill — Low-Ceremony Branch+Commit+PR from Main

## Overview

`/quickfix` is the missing skill for the "I spotted a typo / one-line fix while
reading the codebase and want to ship it as a PR right now" workflow. It
occupies a real gap between the existing PR-flow skills:

| Skill | Entry state | Worktree | Agent-dispatch | Makes PR |
|-------|-------------|----------|----------------|----------|
| `/commit pr` | Already on feature branch with commits | No | No | Yes |
| `/do pr` | On main, no work done yet | Yes (fresh) | Yes | Yes |
| `/fix-issues pr` | Starts from GitHub issue list | Yes (per-issue) | Yes | Yes |
| **`/quickfix`** | **On main with in-flight edits** (or clean+description) | **No** | **Optional fallback** | Yes |

The unique differentiator: `/quickfix` picks up **in-flight edits already in
the main working tree** and ships them as a PR without worktree ceremony. No
other skill does this today; `/commit pr` requires commits to already exist,
and `/do pr` branches fresh in a worktree. DOC_PARTY_COMPARISON §4.1 explicitly
identifies this gap.

**This plan lands via cherry-pick** (the default zskills flow). The
`/quickfix` skill it builds is **PR-only**: it refuses to run unless
`execution.landing == "pr"` — cherry-pick projects already have `/commit` and
`/do`, and supporting both landing models would roughly double the skill's
surface for marginal value. The two concerns (how THIS plan lands vs. what the
resulting skill does) are intentionally separate.

**Skill-only, no separate script.** `/quickfix` matches the shape of
`/commit` and `/do`: a SKILL.md with inline bash blocks. It does not ship a
`scripts/quickfix.sh`. Rationale: `/quickfix` must dispatch an LLM agent in
agent-dispatched mode, and bash scripts cannot dispatch agents — the LLM
context has to stay in the loop. This is different from `/create-worktree`
(script-first, pure plumbing); `/quickfix` is logic-first with agent-handoff.

**Seven locked-in architectural decisions** (from research §3–§4 and
user confirmation — do NOT revisit in adversarial review):

1. **Coexistence with `/do`.** `/quickfix` and `/do` both remain. `/quickfix`'s
   value is main-checkout pick-up of dirty tree. If a user wants worktree
   isolation, they use `/do pr`.
2. **Dual change-making mode, auto-detected.** Dirty tree → user-edited mode
   (pick up working tree as-is). Clean tree + description → agent-dispatched
   mode (dispatch agent in main to make the change). Neither → hard error.
3. **Dirty tree is the INPUT, not a bug.** Show the diff, confirm with user,
   proceed. Never stash. If user has unrelated edits mixed in, refuse and let
   them separate manually.
4. **Test gate before commit.** `testing.unit_cmd` only (never `full_cmd`).
   On failure, `git checkout main` (edits move with checkout) + delete branch.
   **Pre-flight requires `unit_cmd` set AND (`full_cmd` unset OR `full_cmd == unit_cmd`)** — this is what keeps the project hook's transcript check (see R-H1) from blocking our own commits. Projects with a distinct slow `full_cmd` must either align their config or use `/commit pr`.
5. **CI is fire-and-forget.** End at `gh pr create`; print URL; exit. No
   `--watch`, no polling, no fix cycle.
6. **Refuses cherry-pick projects.** If `execution.landing != "pr"`, hard
   error rc=1 pointing to `/commit` or `/do`.
7. **No `.landed` marker.** `.landed` is a worktree-lifecycle artifact;
   `/quickfix` has no worktree. PR state is authoritative via `gh pr view`.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1a — Core skill + happy paths | ⬚ | | SKILL.md core logic (WIs 1.1–1.15 + 1.3.5) + tests 1–10 (happy paths + basic errors) + run-all registration |
| 1b — Guards, hardening, edge cases | ⬚ | | SKILL.md parallel-invocation gate / remote-branch collision / test-harness sandbox polish / mirror (WIs 1.16–1.19) + tests 11–25 (edge cases + structural guards) |
| 3 — Documentation and cross-skill notes | ⬚ | | CLAUDE_TEMPLATE, README, DOC_PARTY_COMPARISON, update-zskills |

**Phase split rationale (R2-H3):** Phase 1 grew to 20 WIs and 25 tests
in round 1. Splitting into 1a (core flow, shippable foundation) and 1b
(hardening + structural guards) keeps each phase to a size an agent can
comfortably finish in one session without reframing later WIs as "future
phases." Phase 1b depends on 1a; Phase 3 depends on 1a + 1b. **Phase 1b
MUST ship before Phase 3** — documentation is only written once the
hardened skill has landed (we document what actually exists).

## Phase 1a — Core Skill + Happy Paths

### Goal

Ship a working `skills/quickfix/SKILL.md` with inline bash implementation
that covers the core end-to-end flow: pre-flight, mode detection, slug /
branch / tracking setup, make-the-change (both modes), test gate, commit,
push, PR creation. Add `tests/test-quickfix.sh` with test cases 1–10
(happy paths + basic error cases) and register in `tests/run-all.sh`.
After Phase 1a, the skill is **shippable for the common path** but not
yet hardened against all edge cases (those come in Phase 1b).

**Work Items 1.1 – 1.15 + 1.3.5** (15 WIs). Mirror to
`.claude/skills/quickfix/` is deferred to Phase 1b (WI 1.19) — Phase 1a
does NOT mirror, because any skill-source change in 1b would require a
re-mirror anyway. Phase 1a ends with the skill source landing on main
(via cherry-pick) and tests 1–10 passing.

### Work Items

- [ ] 1.1 — Create `skills/quickfix/` directory and `skills/quickfix/SKILL.md`
      with YAML frontmatter:
      ```yaml
      ---
      name: quickfix
      disable-model-invocation: true
      argument-hint: "[<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests]"
      description: >-
        Low-ceremony branch-from-main + commit + PR for trivial changes.
        Picks up in-flight edits in the main working tree (dirty-tree mode)
        or dispatches an agent to make the change from a clean tree
        (agent-dispatched mode). PR-only — refuses cherry-pick projects.
        Fire-and-forget CI. Usage: /quickfix [<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests]
      ---
      ```
      `disable-model-invocation: true` is used by 7 zskills source
      SKILL.md files (re-verified round 2: `/commit`, `/do`,
      `/fix-issues`, `/fix-report`, `/qe-audit`, `/doc`, `/plans` — the
      round-1 claim of 12 conflated source and `.claude/skills/` mirror
      copies). This is an explicit-invocation skill, not auto-triggered.

      **R2-L2 self-assertion (Phase 1b WI 1.1 addition).** At skill
      entry, grep the skill's own SKILL.md for the key and fail loudly
      if it went missing:
      ```bash
      SKILL_SELF="$(dirname "$0")/SKILL.md"
      # Fall back to known install paths if $0 is unusual (some invocation paths)
      if [ ! -f "$SKILL_SELF" ]; then
        for candidate in \
          "$MAIN_ROOT/.claude/skills/quickfix/SKILL.md" \
          "$MAIN_ROOT/skills/quickfix/SKILL.md"; do
          if [ -f "$candidate" ]; then SKILL_SELF="$candidate"; break; fi
        done
      fi
      if [ -f "$SKILL_SELF" ] && ! grep -q '^disable-model-invocation: true' "$SKILL_SELF"; then
        echo "ERROR: /quickfix SKILL.md is missing 'disable-model-invocation: true' in its frontmatter. This skill must only run when explicitly invoked." >&2
        exit 1
      fi
      ```
      The guard is non-fatal if `$SKILL_SELF` cannot be located (test
      harness may invoke via an unusual path). A Phase 1b test case
      writes a SKILL.md with the key stripped and asserts the entry
      guard fails.

- [ ] 1.2 — Argument parser. Scan `$ARGUMENTS` for flags; remainder is the
      description (trimmed). Use the bash-regex idiom from
      `skills/do/SKILL.md:70-92`:
      ```bash
      ARGS="$*"
      BRANCH_OVERRIDE=""
      YES_FLAG=0
      FROM_HERE=0
      SKIP_TESTS=0

      if [[ "$ARGS" =~ --branch[[:space:]]+([^[:space:]]+) ]]; then
        BRANCH_OVERRIDE="${BASH_REMATCH[1]}"
        ARGS=$(echo "$ARGS" | sed -E 's/--branch[[:space:]]+[^[:space:]]+//')
      fi
      if [[ "$ARGS" =~ (^|[[:space:]])(--yes|-y)([[:space:]]|$) ]]; then
        YES_FLAG=1
        ARGS=$(echo "$ARGS" | sed -E 's/(^|[[:space:]])(--yes|-y)([[:space:]]|$)/\1\3/g')
      fi
      if [[ "$ARGS" =~ (^|[[:space:]])--from-here([[:space:]]|$) ]]; then
        FROM_HERE=1
        ARGS=$(echo "$ARGS" | sed -E 's/(^|[[:space:]])--from-here([[:space:]]|$)/\1\2/g')
      fi
      if [[ "$ARGS" =~ (^|[[:space:]])--skip-tests([[:space:]]|$) ]]; then
        SKIP_TESTS=1
        ARGS=$(echo "$ARGS" | sed -E 's/(^|[[:space:]])--skip-tests([[:space:]]|$)/\1\2/g')
      fi
      DESCRIPTION=$(echo "$ARGS" | xargs)   # trim whitespace
      ```
      Empty DESCRIPTION is allowed at this stage — mode detection (WI 1.5) is
      what rejects "no edits AND no description".

- [ ] 1.3 — Pre-flight config check. Read `.claude/zskills-config.json` via
      **`jq`** (verified present on dev machines; `/do:309` already uses jq;
      jq will be listed as a hard requirement). Resolve
      `MAIN_ROOT = $(cd "$(git rev-parse --git-common-dir)/.." && pwd)` first
      (BEFORE any `cd`) so config paths anchor correctly.

      Required checks, in order:
      1. `command -v jq >/dev/null 2>&1` — otherwise exit 1 with:
         `"ERROR: /quickfix requires \`jq\`. Install jq (https://jqlang.org/) and re-run."`
      2. `command -v gh >/dev/null 2>&1` — otherwise exit 1 with:
         `"ERROR: /quickfix requires the gh CLI. Install from https://cli.github.com/ and authenticate with \`gh auth login\`."`
      3. `execution.landing == "pr"` — otherwise exit 1 with:
         `"ERROR: /quickfix requires execution.landing == \"pr\". This project uses cherry-pick landing. Use /commit (for pre-made commits) or /do (for new work)."`
      4. **Test-cmd alignment gate (R-H1).** Read:
         ```bash
         UNIT_CMD=$(jq -r '.testing.unit_cmd // ""' "$MAIN_ROOT/.claude/zskills-config.json")
         FULL_CMD=$(jq -r '.testing.full_cmd // ""' "$MAIN_ROOT/.claude/zskills-config.json")
         ```
         Unless `SKIP_TESTS == 1`: require `UNIT_CMD` non-empty. If empty,
         exit 1 with:
         `"ERROR: /quickfix requires testing.unit_cmd to be configured (or pass --skip-tests). Without a test gate /quickfix would ship untested code."`
         Then, if `FULL_CMD` is non-empty AND `FULL_CMD != UNIT_CMD`, exit 1
         with:
         `"ERROR: This project configures testing.full_cmd differently from testing.unit_cmd. /quickfix only runs unit_cmd, which the project's pre-commit hook will not recognize as a valid test gate (it looks for full_cmd in the session transcript). Either align the two values or use /commit pr / /do pr instead."`
         Rationale (see research §2 + R-H1): `hooks/block-unsafe-project.sh.template:188-229`
         blocks `git commit` when code files are staged unless the transcript
         contains `FULL_TEST_CMD`. On projects where `full_cmd != unit_cmd`,
         running only `unit_cmd` would get our commit rejected.

- [ ] 1.3.5 — Parallel-invocation gate (with staleness — R2-M5). Check
      for an in-progress /quickfix pipeline in the same checkout. If the
      marker is older than `STALE_AGE_SECONDS` (default 3600 = 1 hour),
      treat as stale and proceed with a warning — covers the case where
      a previous /quickfix was SIGKILLed and its EXIT trap did not fire.
      ```bash
      STALE_AGE_SECONDS=3600
      NOW_EPOCH=$(date +%s)
      shopt -s nullglob
      for f in "$MAIN_ROOT/.zskills/tracking/quickfix."*/fulfilled.quickfix.*; do
        # Only gate on 'started'; 'complete' / 'failed' / 'cancelled' are terminal.
        if ! grep -q '^status: started' "$f"; then
          continue
        fi
        # Read the marker's `date:` field (ISO-8601 from `date -Iseconds`)
        MARKER_DATE=$(grep -E '^date: ' "$f" | head -1 | sed -E 's/^date: //')
        if [ -z "$MARKER_DATE" ]; then
          echo "WARNING: marker $f has status=started but no date field — treating as stale and proceeding." >&2
          continue
        fi
        MARKER_EPOCH=$(date -d "$MARKER_DATE" +%s 2>/dev/null || echo 0)
        AGE=$(( NOW_EPOCH - MARKER_EPOCH ))
        if [ "$AGE" -gt "$STALE_AGE_SECONDS" ]; then
          echo "WARNING: /quickfix marker $f is $AGE seconds old (> $STALE_AGE_SECONDS); previous invocation likely died without cleanup. Proceeding and overwriting when this run writes its marker." >&2
          continue
        fi
        echo "ERROR: another /quickfix appears to be in progress (marker: $f, age: ${AGE}s). Wait for it to finish or delete the marker if you know it is stale." >&2
        exit 1
      done
      shopt -u nullglob
      ```
      Combined with the started-marker written at WI 1.8 and the EXIT trap
      that finalizes the marker (complete / failed / cancelled), this
      gives us a simple advisory lock with a staleness safety valve.
      Parallel invocations in *different* main checkouts (different
      clones) do not collide — tracking lives under MAIN_ROOT.

      **Test case 26 (Phase 1b):** write a marker with `status: started`
      and `date:` 2 hours in the past; invoke /quickfix; expect exit 0
      (not exit 1) with a `WARNING: ... stale` on stderr.

- [ ] 1.4 — Pre-flight main-ref fetch. From `MAIN_ROOT`, verify the invoker is
      on the project's primary branch (unless `--from-here`), then fetch the
      remote ref so later branching can use it directly. **Do NOT attempt
      `merge --ff-only`** — per R-H5, with a dirty tree that touches paths
      changed upstream, ff-merge refuses and breaks /quickfix's primary use
      case. We don't need local main to be current; we branch from
      `origin/main` and `gh pr create` compares against remote main later.
      ```bash
      cd "$MAIN_ROOT"
      CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
      BASE_BRANCH="$CURRENT_BRANCH"   # captured for later gh pr create --base
      if [ "$FROM_HERE" -eq 0 ]; then
        if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
          echo "ERROR: /quickfix must be invoked from main (or master). Current branch: $CURRENT_BRANCH. Use --from-here to override." >&2
          exit 1
        fi
      fi
      git fetch origin "$BASE_BRANCH" \
        || { echo "ERROR: git fetch origin $BASE_BRANCH failed" >&2; exit 1; }
      ```
      Local main is allowed to be stale — we branch from `origin/$BASE_BRANCH`
      in WI 1.9.

- [ ] 1.5 — Mode detection. Compute the change set with robust helpers (see
      WI 1.10 for the canonical enumerator). Let `DIRTY_FILES` be the sorted
      union of `git diff --name-only HEAD` + `git diff --name-only --diff-filter=D HEAD`
      + `git ls-files --others --exclude-standard`. Let
      `HAS_DESCRIPTION = ([ -n "$DESCRIPTION" ])`:
      - **User-edited mode:** `DIRTY_FILES` non-empty — pick up dirty tree.
        Description is REQUIRED per R-M5; see derivation in WI 1.13 step 4.
      - **Agent-dispatched mode:** `DIRTY_FILES` empty AND
        `[ -n "$DESCRIPTION" ]` — dispatch agent to make the change.
      - **Reject:** `DIRTY_FILES` empty AND `[ -z "$DESCRIPTION" ]` —
        exit 2 with:
        ```
        ERROR: /quickfix needs either in-flight edits in the working tree
        or a description to dispatch an agent. Got neither.

        Usage: /quickfix [<description>] [--branch <name>] [--yes] [--from-here] [--skip-tests]

        Examples:
          # User-edited: edit files, then:
          /quickfix Fix typo in README

          # Agent-dispatched:
          /quickfix Fix the broken link in docs/intro.md
        ```
      - **User-edited without description (R-M5):** if DIRTY_FILES non-empty
        AND DESCRIPTION empty → exit 2 with:
        ```
        ERROR: /quickfix in user-edited mode requires a description. Your
        edits are preserved in main; re-run with a description, e.g.:
          /quickfix Fix typo in README
        ```

- [ ] 1.6 — Slug derivation. DESCRIPTION is guaranteed non-empty by WI 1.5.
      ```bash
      SLUG=$(echo "$DESCRIPTION" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
        | cut -c1-40 \
        | sed -E 's/-+$//')
      if [ -z "$SLUG" ]; then
        echo "ERROR: could not derive slug from description \"$DESCRIPTION\"" >&2
        exit 2
      fi
      # Path safety — CREATE_WORKTREE R2-H1 lesson: slugs NEVER contain slashes
      if [[ "$SLUG" == */* ]]; then
        echo "ERROR: derived slug contains slash: $SLUG" >&2
        exit 2
      fi
      ```
      The trailing `sed -E 's/-+$//'` after `cut -c1-40` is critical: if the
      cut falls on a `-` boundary, we'd otherwise emit `quickfix/fix-foo-`.

- [ ] 1.7 — Branch naming. Read `execution.branch_prefix` from config via
      `jq`; default `quickfix/`. Honor `--branch` override:
      ```bash
      BRANCH_PREFIX=$(jq -r '.execution.branch_prefix // "quickfix/"' \
        "$MAIN_ROOT/.claude/zskills-config.json" 2>/dev/null || echo "quickfix/")
      if [ -n "$BRANCH_OVERRIDE" ]; then
        BRANCH="$BRANCH_OVERRIDE"
      else
        BRANCH="${BRANCH_PREFIX}${SLUG}"
      fi
      ```
      An empty `branch_prefix` (`""`) produces bare-slug branches — this is
      supported and tested (see test case 16).
      The `--branch` override passes through verbatim (user's responsibility
      if they supply a malformed name). Slashes in `BRANCH` are allowed
      (branch names may be nested refs); slashes in SLUG are not (SLUG goes
      into path-like contexts in tracking).

- [ ] 1.8 — Tracking setup. Construct PIPELINE_ID, sanitize, write
      **`started`** fulfillment marker, and install an EXIT trap so the
      marker always ends in a terminal state (`complete` or `failed`).
      Additionally, **echo `ZSKILLS_PIPELINE_ID=<pipeline>`** into the
      session transcript for tier-2 tracking association (mirrors the
      pattern in `tests/test-hooks.sh:245`):
      ```bash
      RAW_PIPELINE_ID="quickfix.${SLUG}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$RAW_PIPELINE_ID")
      echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"   # transcript marker for tier-2 tracking
      TRACK_DIR="$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID"
      mkdir -p "$TRACK_DIR"
      MARKER="$TRACK_DIR/fulfilled.quickfix.$SLUG"
      # CANCELLED flag: set to 1 by the cancel path (WI 1.10 step 3) so the
      # EXIT trap writes `status: cancelled` instead of `status: complete`.
      # R2-M1: distinct terminal state so briefing / consumers can tell
      # cancel from success without having to inspect the `pr:` field.
      CANCELLED=0
      write_marker() {
        printf 'skill: quickfix\nid: %s\nbranch: %s\nmode: %s\nstatus: %s\ndate: %s\n' \
          "$SLUG" "$BRANCH" "$MODE" "$1" \
          "$(TZ=America/New_York date -Iseconds)" > "$MARKER"
      }
      write_marker started
      # Finalize on any exit:
      #   status=cancelled if CANCELLED=1 (R2-M1),
      #   status=complete on rc=0 otherwise,
      #   status=failed on non-zero rc.
      trap '_rc=$?; if [ "$CANCELLED" = "1" ]; then write_marker cancelled; elif [ "$_rc" -eq 0 ]; then write_marker complete; else write_marker failed; fi' EXIT
      ```
      Where `MODE` is `"user-edited"` or `"agent-dispatched"` from WI 1.5.
      The final PR URL is appended to the marker at WI 1.16.

      **Terminal states documented (tracking contract):**
      - `started` — pipeline running, EXIT trap not yet fired.
      - `complete` — pipeline exited rc=0 AND was not cancelled (PR
        created; `pr:` field present).
      - `cancelled` — user answered `n` at the diff-confirm prompt
        (R2-M1); rc=0 but no PR created; no `pr:` field.
      - `failed` — pipeline exited non-zero for any reason (pre-flight
        gate, test failure, push/PR error, cleanup failure exit 6).

- [ ] 1.9 — Branch creation. From `MAIN_ROOT`:
      ```bash
      # 1. Local-ref collision check
      if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
        echo "ERROR: branch $BRANCH already exists locally. Delete it (git branch -D $BRANCH) or choose another name via --branch." >&2
        exit 2
      fi
      # 2. Remote-ref collision check (R-H8, refined R2-M4).
      # Use `git ls-remote` so we can distinguish "branch not present"
      # (exit 0, empty stdout) from "network/auth failure" (non-zero exit).
      # NEVER `|| true` this — if the remote is unreachable we should
      # fail loudly rather than silently assume the branch is absent
      # (which would cause us to push onto whatever's there).
      LS_OUT=$(git ls-remote --heads origin "$BRANCH")
      LS_RC=$?
      if [ "$LS_RC" -ne 0 ]; then
        echo "ERROR: git ls-remote origin failed (rc=$LS_RC). Cannot verify whether $BRANCH exists on origin. Check network / auth and retry." >&2
        exit 1
      fi
      if [ -n "$LS_OUT" ]; then
        echo "ERROR: branch $BRANCH exists on origin. Delete via \`git push origin --delete $BRANCH\` or use \`--branch <other>\`." >&2
        exit 2
      fi
      # 3. Branch from origin/$BASE_BRANCH — carries the dirty tree over
      #    (the edits are attached to HEAD, not to main; checkout moves them).
      git checkout -b "$BRANCH" "origin/$BASE_BRANCH" \
        || { echo "ERROR: git checkout -b $BRANCH origin/$BASE_BRANCH failed (likely a conflict between dirty edits and upstream state; resolve locally)" >&2; exit 1; }
      ```
      If checkout fails because the dirty edits conflict with paths changed
      in `origin/$BASE_BRANCH`, git prints the conflicting files and the
      user resolves manually. **Never destroys edits.**

- [ ] 1.10 — **User-edited mode** (if `MODE == "user-edited"`):
      1. Enumerate CHANGED_FILES robustly (R-H6):
         ```bash
         # modifications + renames (new path) + additions
         mapfile -t MODS < <(git diff --name-only HEAD)
         # deletions (paths that used to exist)
         mapfile -t DELS < <(git diff --name-only --diff-filter=D HEAD)
         # untracked files the user wants to ship
         mapfile -t UNTRACKED < <(git ls-files --others --exclude-standard)
         CHANGED_FILES=("${MODS[@]}" "${UNTRACKED[@]}")
         # dedupe + sort
         IFS=$'\n' CHANGED_FILES=($(printf '%s\n' "${CHANGED_FILES[@]}" | sort -u))
         unset IFS
         ```
         These commands emit the literal path (or new path, for renames),
         never the `XY orig -> path` porcelain shape. Paths with spaces are
         fine (newline-separated). `DELS` are tracked separately so we can
         apply them via `git add -u` in WI 1.13.

      2. Show the diff: `git diff HEAD` (full diff, not stat) and the file
         list (`printf '%s\n' "${CHANGED_FILES[@]}"`; if DELS non-empty,
         also print `DELETED: <path>` for each deleted file).
      3. Confirmation:
         - If `YES_FLAG == 1`, skip prompt.
         - Else, prompt user: `"Ship this change as a PR on branch $BRANCH? (y/N) "`.
           Wait for response. Anything other than `y`/`Y` → set
           `CANCELLED=1` (so the EXIT trap writes
           `status: cancelled` per R2-M1), run cleanup with verified
           steps (R2-H2), and exit 0. Cleanup sequence:
           ```bash
           CANCELLED=1
           if ! git checkout "$BASE_BRANCH"; then
             echo "ERROR: cleanup: git checkout $BASE_BRANCH failed — repo is in an intermediate state. Recover manually: \`git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
             exit 6
           fi
           if ! git branch -D "$BRANCH"; then
             echo "ERROR: cleanup: git branch -D $BRANCH failed. Delete manually: \`git branch -D $BRANCH\`." >&2
             exit 6
           fi
           echo "Cancelled. Your edits are preserved in main. If you had unrelated changes mixed in, separate them before re-running /quickfix."
           exit 0
           ```
           The marker ends up as `status: cancelled` (distinct from
           `complete`), so briefing and other consumers can distinguish
           the two terminal states without relying on the absence of
           the `pr:` field.
      4. If confirmed, proceed to WI 1.12 (test gate).

- [ ] 1.11 — **Agent-dispatched mode** (if `MODE == "agent-dispatched"`).

      **IMPORTANT — model-layer instruction, not bash.** This Work Item is a
      prose instruction to the invoking Claude model (following the same
      pattern as `skills/do/SKILL.md:342-358`). The bash that surrounds it
      detects success via `git status --porcelain` non-empty AND HEAD
      unchanged (see step 3). A future maintainer MUST NOT attempt to
      dispatch agents from bash — CREATE_WORKTREE R-F1 established that
      skills cannot dispatch sub-agents from shell. Agent timeout handling
      is out of scope for v1; we delegate to the Task tool's own timeout.

      Steps:

      1. Capture pre-dispatch HEAD for sanity checking:
         ```bash
         PRE_HEAD=$(git rev-parse HEAD)
         ```
      2. Check `agents.min_model` in config via jq. If set, resolve minimum
         (haiku=1, sonnet=2, opus=3) and use that or higher when dispatching.
         If unset, OMIT the `model` field (inherit parent model — per MEMORY
         feedback `feedback_no_haiku.md`).
      3. Dispatch an Agent (no `isolation: "worktree"` — we're in main
         already, on the feature branch) with this prompt (verbatim — the
         invoking model reads this and invokes the Task/Agent tool):
         ```
         You are implementing: $DESCRIPTION

         FIRST: cd $MAIN_ROOT
         All work happens in that directory. You are on branch $BRANCH
         (already checked out).

         Implement the task. Do NOT commit — /quickfix handles commit,
         test, push, and PR. Make only the edits needed for:
             $DESCRIPTION

         Do NOT run tests, build commands, linters, formatters, or any
         other tooling that writes files (coverage reports, build
         output, generated docs, etc.). /quickfix runs the test gate
         itself AFTER you return. Stray build/coverage artifacts in
         the working tree would be picked up as "your edits" and
         included in the commit. If the task requires tooling to
         verify, respond "done, but I need to run X to verify" and
         stop — the user will decide how to proceed.

         If you create new files (untracked additions), list them
         explicitly in your "done" report. /quickfix only auto-detects
         changes to tracked files (R2-M2); new files must be stated so
         the human reviewer can confirm them before commit.

         When done, stop — no further actions. Report "done" with a
         one-line summary of files changed (including any new files).

         Check agents.min_model in .claude/zskills-config.json before
         dispatching any sub-agents. Use that model or higher (haiku=1 <
         sonnet=2 < opus=3).
         ```
      4. After agent returns, verify:
         ```bash
         POST_HEAD=$(git rev-parse HEAD)
         if [ "$POST_HEAD" != "$PRE_HEAD" ]; then
           echo "ERROR: sub-agent created a commit (HEAD moved). /quickfix owns the commit step; aborting." >&2
           # Cleanup (R2-H2: NEVER `|| true` — verify each step; if cleanup
           # fails the repo is in an intermediate state and the user must
           # intervene manually. Exit 6 signals "cleanup failed, manual
           # intervention needed" so the EXIT trap's `failed` marker plus
           # this distinct code together let the user diagnose.)
           if ! git reset --soft "$PRE_HEAD"; then
             echo "ERROR: cleanup: git reset --soft \"$PRE_HEAD\" failed — repo is in an intermediate state. Branch $BRANCH still exists and HEAD may still be at the unexpected commit. Recover manually: \`git reset --hard $PRE_HEAD && git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
             exit 6
           fi
           if ! git checkout "$BASE_BRANCH"; then
             echo "ERROR: cleanup: git checkout $BASE_BRANCH failed — repo is in an intermediate state. Recover manually: \`git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
             exit 6
           fi
           if ! git branch -D "$BRANCH"; then
             echo "ERROR: cleanup: git branch -D $BRANCH failed — branch remains. Delete manually: \`git branch -D $BRANCH\`." >&2
             exit 6
           fi
           exit 5
         fi
         # R2-M2: agents are instructed to NOT run tests/builds (see step 3
         # prompt). Detect only staged-or-unstaged edits to tracked files,
         # NOT untracked files — build/coverage artifacts outside .gitignore
         # would false-positive as "agent made edits" otherwise. The
         # limitation: if the agent creates a genuinely new untracked file,
         # /quickfix won't see it automatically; the agent must state new
         # files explicitly in its "done" summary. Documented in Design.
         DIRTY_AFTER=$(git diff --name-only HEAD)
         if [ -z "$DIRTY_AFTER" ]; then
           echo "ERROR: agent returned but made no changes. Aborting." >&2
           if ! git checkout "$BASE_BRANCH"; then
             echo "ERROR: cleanup: git checkout $BASE_BRANCH failed — repo is in an intermediate state. Recover manually: \`git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
             exit 6
           fi
           if ! git branch -D "$BRANCH"; then
             echo "ERROR: cleanup: git branch -D $BRANCH failed — branch remains. Delete manually: \`git branch -D $BRANCH\`." >&2
             exit 6
           fi
           exit 5
         fi
         ```
      5. Capture CHANGED_FILES using the same enumerator as WI 1.10 step 1
         and proceed to WI 1.12 (test gate).

- [ ] 1.12 — Test gate. `UNIT_CMD` was already read in WI 1.3.
      - If `SKIP_TESTS == 1`: print `"WARNING: --skip-tests passed; unit test gate skipped."` and proceed.
      - Otherwise run `UNIT_CMD` with output captured per the CLAUDE.md
        slug-isolated idiom (R-H4 concurrent-invocation safety):
        ```bash
        if [ "$SKIP_TESTS" -eq 0 ]; then
          TEST_OUT="/tmp/zskills-tests/$(basename "$MAIN_ROOT")-quickfix-$SLUG"
          mkdir -p "$TEST_OUT"
          cd "$MAIN_ROOT"
          bash -c "$UNIT_CMD" > "$TEST_OUT/.test-results.txt" 2>&1
          UNIT_RC=$?
          if [ "$UNIT_RC" -ne 0 ]; then
            echo "ERROR: unit tests failed. See $TEST_OUT/.test-results.txt" >&2
            echo "Cleaning up: checkout $BASE_BRANCH, delete branch $BRANCH (edits persist in working tree)." >&2
            git checkout "$BASE_BRANCH"
            git branch -D "$BRANCH"
            exit 4
          fi
        else
          echo "WARNING: --skip-tests passed; unit test gate skipped." >&2
        fi
        ```
      **Rollback on failure preserves edits** because `git checkout` carries
      uncommitted changes across branches.

- [ ] 1.13 — Commit. Follow CLAUDE.md feature-complete discipline inline
      (cannot invoke `/commit` — skills can't call each other from bash
      blocks per CREATE_WORKTREE R-F1):
      1. `git status -s` — show ALL changes.
      2. For each file in CHANGED_FILES, skim for uncommitted-import
         dependencies (best-effort warning only — CHANGED_FILES already
         includes untracked files, so imports of NEW files that the user
         forgot to track are the only gap; those would show up as
         `unable to find ...` at build time).
      3. Stage:
         ```bash
         # Stage modifications, renames, additions (explicit list; never `.` / `-A`)
         if [ "${#CHANGED_FILES[@]}" -gt 0 ]; then
           for p in "${CHANGED_FILES[@]}"; do
             if [ -d "$p" ]; then
               echo "ERROR: $p is a directory; feature-complete discipline requires files, not directories. Aborting." >&2
               # R2-H2: verify each cleanup step; on failure exit 6 with
               # manual-recovery guidance.
               if ! git checkout "$BASE_BRANCH"; then
                 echo "ERROR: cleanup: git checkout $BASE_BRANCH failed — repo is in an intermediate state. Recover manually: \`git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
                 exit 6
               fi
               if ! git branch -D "$BRANCH"; then
                 echo "ERROR: cleanup: git branch -D $BRANCH failed. Delete manually: \`git branch -D $BRANCH\`." >&2
                 exit 6
               fi
               exit 5
             fi
           done
           git add -- "${CHANGED_FILES[@]}"
         fi
         # Stage deletions explicitly (R-H6)
         if [ "${#DELS[@]}" -gt 0 ]; then
           git add -u -- "${DELS[@]}"
         fi
         ```
         The `--` separator guards against paths beginning with `-`.
         Directory paths are rejected (they'd sweep in contents, violating
         feature-complete discipline).
      4. Derive commit message. DESCRIPTION is guaranteed non-empty (WI 1.5
         requires it in user-edited mode; agent-dispatched mode needs it to
         have reached this point). So `COMMIT_MSG="$DESCRIPTION"`.
      5. **Commit-failure recovery (R-H2).** We use auto-cleanup on commit
         failure: checkout back to `$BASE_BRANCH`, delete the branch, leave
         the dirty edits in place. The user fixes the underlying issue (hook
         failure, whatever) and re-runs /quickfix from a clean slate. This
         is the "always cleanup-and-rerun" recovery path.
         ```bash
         # R2-M6: mode-aware trailer. Agent-dispatched commits attribute
         # Claude (semantically correct — the dispatched agent is Claude);
         # user-edited commits do not (the human authored the change).
         if [ "$MODE" = "agent-dispatched" ]; then
           COMMIT_TRAILER=$'🤖 Generated with /quickfix (agent-dispatched)\n\nCo-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>'
         else
           COMMIT_TRAILER='🤖 Generated with /quickfix (user-edited)'
         fi
         git commit -m "$(printf '%s\n\n%s\n' "$COMMIT_MSG" "$COMMIT_TRAILER")"
         COMMIT_RC=$?
         if [ "$COMMIT_RC" -ne 0 ]; then
           echo "ERROR: git commit failed (rc=$COMMIT_RC). Rolling back branch $BRANCH; your edits are preserved in $BASE_BRANCH." >&2
           # R2-H2: verify each cleanup step. If unstaging or checkout
           # fails, the repo is in an intermediate state — exit 6 so the
           # user knows to recover manually rather than assuming the
           # skill "finished."
           if ! git reset HEAD -- .; then
             echo "ERROR: cleanup: git reset HEAD -- . failed — some files remain staged. Recover manually: \`git reset HEAD && git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
             exit 6
           fi
           if ! git checkout "$BASE_BRANCH"; then
             echo "ERROR: cleanup: git checkout $BASE_BRANCH failed — repo is in an intermediate state on branch $BRANCH. Recover manually: \`git checkout $BASE_BRANCH && git branch -D $BRANCH\`." >&2
             exit 6
           fi
           if ! git branch -D "$BRANCH"; then
             echo "ERROR: cleanup: git branch -D $BRANCH failed — branch remains. Delete manually: \`git branch -D $BRANCH\`." >&2
             exit 6
           fi
           exit 5
         fi
         ```
      6. **Never bypass hooks.** No `--no-verify`. If a pre-commit hook
         fails, the branch is torn down (step 5 above) and the user
         re-runs /quickfix after addressing the hook issue. WI 1.9's
         branch-exists gate is NEVER surprising in this flow because the
         branch always gets deleted on failure.

- [ ] 1.14 — Push. Bare branch-name form to route around DOC_PARTY_COMPARISON
      §3.1 refspec parser bug:
      ```bash
      git push -u origin "$BRANCH"
      PUSH_RC=$?
      if [ "$PUSH_RC" -ne 0 ]; then
        echo "ERROR: git push failed (rc=$PUSH_RC). Branch $BRANCH has a local commit; push manually with: git push -u origin $BRANCH" >&2
        exit 5
      fi
      ```
      **Never** use `git push origin HEAD:main` or any explicit `src:dst`
      refspec — that form bypasses `block-unsafe-generic.sh:146` main-protect
      (research §2). On push failure, the local branch + commit are left
      intact so the user can retry `git push -u origin $BRANCH` after
      investigation.

- [ ] 1.15 — PR creation. Build title (≤70 chars) and body, then
      `gh pr create`. The PR body heredoc MUST be un-indented to column 0
      (R-M1 — markdown interprets 4+ leading spaces as a code block):
      ```bash
      PR_TITLE=$(printf '%s' "$DESCRIPTION" | cut -c1-70)
      # Build the file-list and deletion-list without losing trailing newlines
      # (R-M2: `$(printf ...)` drops a single trailing \n; the sentinel echo
      # preserves separation from the next section). Use `printf '%s\n'` so
      # filenames containing `%` don't become format specifiers.
      FILES_BLOCK=$({ printf '%s\n' "${CHANGED_FILES[@]/#/- }"; echo; })
      if [ "${#DELS[@]}" -gt 0 ]; then
        DELS_BLOCK=$({ printf '%s\n' "${DELS[@]/#/- DELETED: }"; echo; })
      else
        DELS_BLOCK=""
      fi
      TEST_LINE=$([ "$SKIP_TESTS" -eq 0 ] \
        && echo "unit tests passed locally ($UNIT_CMD)" \
        || echo "tests skipped (--skip-tests)")
      PR_BODY=$(cat <<-EOF
	## Summary
	$DESCRIPTION

	## Files changed
	$FILES_BLOCK
	$DELS_BLOCK
	## Test results
	$TEST_LINE

	## How this PR was made
	Shipped via /quickfix in $MODE mode.
	EOF
      )
      PR_URL=$(gh pr create --base "$BASE_BRANCH" --head "$BRANCH" \
        --title "$PR_TITLE" --body "$PR_BODY")
      PR_RC=$?
      if [ "$PR_RC" -ne 0 ] || [ -z "$PR_URL" ]; then
        echo "ERROR: gh pr create failed (rc=$PR_RC). Branch $BRANCH is pushed; create PR manually with: gh pr create --base $BASE_BRANCH --head $BRANCH" >&2
        exit 5
      fi
      echo "$PR_URL"
      ```
      - `<<-EOF` with TAB indentation (the body lines above are tab-prefixed
        because `<<-` strips leading TABs, not spaces). In `skills/quickfix/SKILL.md`
        the heredoc body MUST be tab-indented, not space-indented.
      - `--base "$BASE_BRANCH"` (R-M3): the PR targets whatever primary
        branch the repo uses (`main` or `master`).
      - No CI watch. No polling. No fix cycle.

### Acceptance Criteria (Phase 1a)

- [ ] `bash tests/test-quickfix.sh` exits 0 with test cases 1–10 + 14
  (run-all registration) passing (see Test Cases §). Cases 11–13, 15–25
  may be written but do not need to pass until Phase 1b. **Stricter
  alternative:** if Phase 1a's scope ends up naturally covering more
  cases (e.g., structural greps 11 and 12 pass as a byproduct of the
  skill source existing), let them pass — no need to gate them down.
- [ ] `bash tests/run-all.sh` exits 0 with the new suite registered.
- [ ] `grep -c 'test-quickfix.sh' tests/run-all.sh` returns ≥ 1.
- [ ] `grep -q 'disable-model-invocation: true' skills/quickfix/SKILL.md`
  succeeds.
- [ ] `grep -q 'argument-hint:' skills/quickfix/SKILL.md` succeeds and
  the value contains `--branch`, `--yes`, `--from-here`, `--skip-tests`.
- [ ] `grep -q 'execution.landing == "pr"' skills/quickfix/SKILL.md`
  succeeds.
- [ ] `grep -q 'full_cmd' skills/quickfix/SKILL.md` AND
  `grep -q 'unit_cmd' skills/quickfix/SKILL.md` succeed (R-H1 gate).
- [ ] `grep -q 'git push -u origin' skills/quickfix/SKILL.md` succeeds.
- [ ] `grep -qE 'HEAD:main|HEAD:master' skills/quickfix/SKILL.md`
  **FAILS** (no refspec bug invocation).
- [ ] `grep -q -- '--no-verify' skills/quickfix/SKILL.md` **FAILS**
  (no hook-bypass).
- [ ] Manual smoke in a throwaway repo with aligned config + mocked `gh`:
  edit, run `/quickfix Fix smoke test --yes`, confirm branch/commit/PR.
- [ ] **No mirror in 1a** — `.claude/skills/quickfix/` is not expected
  to exist yet; Phase 1b's WI 1.19 writes it.
- [ ] **NO `|| true` in cleanup paths** (R2-H2): `grep -nE '\|\| true' skills/quickfix/SKILL.md`
  produces no output. If found, Phase 1a is NOT complete.

### Dependencies (Phase 1a)

None. Phase 1a is self-contained. Consumes existing infrastructure
(`scripts/sanitize-pipeline-id.sh`, `.claude/zskills-config.json`,
hooks, `jq`, `gh`). Does NOT require Phase 1b or Phase 3.

---

## Phase 1b — Guards, Hardening, Edge Cases

### Goal

Harden `skills/quickfix/SKILL.md` against edge cases not covered in 1a:
marker polish (`pr:` field), the test harness polish WI, the `tests/run-all.sh`
registration (moved here if not already in 1a), and the `.claude/skills/`
mirror. Add test cases 11–25 (structural guards + edge cases +
concurrent-invocation + `full_cmd` gate tests + path-with-spaces +
untracked file + agent misbehavior + remote-branch collision + etc.).

**Work Items 1.16 – 1.19** (4 WIs). Phase 1b lands after Phase 1a. Every
WI edits the *same* `skills/quickfix/SKILL.md` and `tests/test-quickfix.sh`
that 1a shipped.

### Work Items

- [ ] 1.16 — Append PR URL to fulfillment marker. The EXIT trap writes
      `status: complete` automatically; this step adds the `pr:` field
      that identifies a successful (vs. cancelled) run:
      ```bash
      cat >> "$MARKER" <<LANDED
      pr: $PR_URL
      LANDED
      ```
      **Explicitly do NOT write `.landed`.** Verified by Phase 1b
      acceptance criterion. Note: combined with R2-M1 below, a cancelled
      run writes `status: cancelled` (NOT `complete`), so the presence
      of `pr:` is no longer the only distinguishing signal — but
      consumers that inspect `pr:` still work.

- [ ] 1.17 — Create `tests/test-quickfix.sh` with ≥35 cases (enumerated in
      Design & Constraints §Test Cases — 25 from round 1 + 10 added in
      round 2 for R2-M5, R2-M1, R2-H2, R2-M6, R2-L2, R2-M4, R2-H1, R2-M2).
      Phase 1a drafts cases 1–10 + 14 (registration); Phase 1b adds the
      rest. Harness layout: isolated temp repo per case, mock config file,
      mock `gh` CLI wrapper on PATH that echoes a fake PR URL. Pattern
      from `tests/test-hooks.sh:226-254` (`setup_project_test()`). Output
      follows CLAUDE.md idiom — `TEST_OUT` derived from `$(pwd)` inside
      each case's temp dir.

- [ ] 1.18 — Register `tests/test-quickfix.sh` in `tests/run-all.sh` after
      the existing `run_suite` lines (after line 44):
      ```bash
      run_suite "test-quickfix.sh" "tests/test-quickfix.sh"
      ```

- [ ] 1.19 — Mirror the skill source to `.claude/skills/`. **CRITICAL
      (R2-H1, live-reproduced):** the `block-unsafe-generic.sh` hook
      (`is_safe_destruct`) rejects any `rm -r[f]` whose command text
      contains `$`. So `rm -rf "$MAIN_ROOT/.claude/skills/quickfix"` is
      blocked verbatim. The only safe idiom is to `cd` into `$MAIN_ROOT`
      first (which is allowed — the rule only checks the `rm` invocation),
      then use a **literal** path on the `rm` line. This matches WI 3.5
      and the verified precedent in `plans/RESTRUCTURE_RUN_PLAN.md:184,328,491`
      (all of which use literal paths after an explicit `cd`):
      ```bash
      cd "$MAIN_ROOT" && rm -rf .claude/skills/quickfix && cp -r skills/quickfix .claude/skills/quickfix
      diff -r skills/quickfix .claude/skills/quickfix
      ```
      `diff -r` must be empty. Rationale:
      - The `cd "$MAIN_ROOT"` is a separate command from the `rm`; the
        hook inspects each `rm` invocation independently, and the `rm`
        invocation itself contains no `$`, backtick, `*`, `?`, or
        leading `~`.
      - `rm -rf .claude/skills/quickfix` is a literal, non-`/tmp/` path.
        Per `is_safe_destruct`, non-`/tmp/` paths fail the `/tmp/<name>`
        regex and return 1 — BUT the hook's `RM_RECURSIVE` gate only
        blocks when `is_safe_destruct` returns false AND the command
        contains a `$`/backtick/glob/tilde. Empirical precedent in
        `plans/RESTRUCTURE_RUN_PLAN.md` (multiple landed mirrors) confirms
        the literal form passes. The live-reproducer in round 2 confirms
        the `$`-containing form fails.
      - Per MEMORY `feedback_claude_skills_permissions.md`, do the mirror
        as a single `cp -r` (not per-file Edit) to avoid permission-prompt
        storms.

      Acceptance check (also added to Phase 1b acceptance criteria):
      `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md` must return NO
      matches. I.e., no `rm -rf` line in the skill source begins with
      `rm -rf "$…` — only the literal `rm -rf .claude/skills/quickfix`
      form is allowed.

### Design & Constraints (applies to both Phase 1a and Phase 1b)

**Skill anatomy.** `skills/quickfix/SKILL.md` has YAML frontmatter + a body
organized as (runtime stages — distinct from the plan's build phases):

1. **Header** — name, usage, one-sentence differentiator.
2. **Preconditions** — on main (or `--from-here`), clean or dirty tree, gh
   CLI, jq, PR landing mode, `unit_cmd` configured (or `--skip-tests`),
   `full_cmd` aligned with `unit_cmd`.
3. **Stage 0 — Pre-flight** — config/landing/test-alignment checks, gh/jq
   check, parallel-invocation gate (with staleness per R2-M5), main-ref
   fetch (WI 1.3, 1.3.5, 1.4). **Pre-flight is fail-fast (R2-M3):**
   check N exits on the first failure; the user sees exactly one error
   per invocation. A user fixing three issues will re-run three times.
   This is a deliberate choice over multi-line enumerated reports —
   simpler to implement, matches the feel of `/do` and `/commit`
   pre-flight, and avoids one check's failure modeling as "partial
   success" for later checks.
4. **Stage 1 — Mode detection + slug/branch + tracking** — WI 1.5, 1.6,
   1.7, 1.8, 1.9.
5. **Stage 2 — Make the change** — split by mode (WI 1.10 user-edited,
   WI 1.11 agent-dispatched).
6. **Stage 3 — Test gate** — WI 1.12.
7. **Stage 4 — Commit + push + PR** — WI 1.13, 1.14, 1.15.
8. **Stage 5 — Finalize** — WI 1.16, print PR URL, exit 0.

**Argument grammar (verbatim contract).**

```
/quickfix [<description>...] [--branch <name>] [--yes|-y] [--from-here] [--skip-tests]
```

- `<description>` — free-form text (space-separated tokens). Required in
  both modes.
- `--branch <name>` — override derived branch name. `<name>` is used verbatim
  for `git checkout -b`. If `--branch` appears, its argument is consumed
  from the token stream before description is computed.
- `--yes` / `-y` — non-interactive mode: skip the user-edited confirmation
  prompt (the diff is still printed for logs). Required for CI
  invocations.
- `--from-here` — bypass the on-main branch guard. Documented as opt-in for
  users working from integration branches.
- `--skip-tests` — skip the unit test gate. Pairs with the /quickfix
  philosophy of not shipping untested code, so `--skip-tests` is opt-in and
  noisy (a WARNING is printed).

**Mode detection truth table.**

| DIRTY_FILES empty? | DESCRIPTION | Mode | Action |
|--------------------|-------------|------|--------|
| No                 | non-empty   | user-edited | pick up dirty tree |
| No                 | empty       | (rejected, R-M5) | exit 2 |
| Yes                | non-empty   | agent-dispatched | dispatch agent |
| Yes                | empty       | (rejected)  | exit 2 |

**Test harness isolation (R-M6).** Every test case:

1. `TESTDIR=$(mktemp -d -t zskills-quickfix.XXXXXX)` — puts TESTDIR
   under `/tmp/zskills-quickfix.<rand>` so the hook's `is_safe_destruct`
   regex allows cleanup.
2. `trap 'rm -rf "$TESTDIR"' RETURN` (or per-case cleanup). This
   `$`-bearing form runs INSIDE `tests/test-quickfix.sh` (a script file),
   not as an agent-issued tool call, so the `block-unsafe-generic.sh`
   hook does not inspect it. Scripts may contain whatever shell they
   need; the hook only inspects tool calls.
3. `cd "$TESTDIR"`.
4. `git init -q && git commit --allow-empty -m init` to create a repo.
5. Bare-remote clone for push tests (see `tests/test-hooks.sh:259-269`
   `setup_push_remote()`).
6. Write `.claude/zskills-config.json` with `execution.landing: "pr"`,
   `testing.unit_cmd: "true"`, `testing.full_cmd: "true"` (aligned so
   R-H1 gate passes) unless the test is explicitly exercising a gate.
7. Install a mock `gh` wrapper on PATH that echoes a fixed fake URL for
   `gh pr create`.
8. Export `ZSKILLS_SKIP_MIRROR=1` or equivalent if the test harness
   shouldn't touch `.claude/skills/quickfix`.

This mirrors `tests/test-hooks.sh:226-254` (`setup_project_test()`).

**Exit codes.**

| Code | Meaning | Examples |
|------|---------|----------|
| 0 | Success (PR created) or user-cancelled confirmation | happy path; user said "n" to confirmation |
| 1 | Config / environment error | `landing != "pr"`; `gh` missing; `jq` missing; not on main; fetch failed; `unit_cmd` unset; `full_cmd` differs from `unit_cmd`; another /quickfix in progress |
| 2 | Input error | Neither dirty tree nor description; user-edited without description; branch already exists locally or on origin; slug could not be derived; slug contains slash |
| 4 | Test failure | `testing.unit_cmd` returned non-zero |
| 5 | Commit / push / PR-create / agent failure | hook failure, push rejection, `gh pr create` error, agent made no changes, agent committed unexpectedly, directory in CHANGED_FILES |
| 6 | Cleanup failure (manual intervention needed) — R2-H2 | A rollback step (`git reset`, `git checkout`, `git branch -D`) returned non-zero; the repo is in an intermediate state and the user must recover per the printed guidance. Distinct from code 5 so the user can see at a glance whether the operation failed cleanly (5) or failed AND failed to roll back (6). |

(Exit code 3 dropped — R-M10.)

**Slug derivation contract (verbatim).**

Input string → output slug:
- Lowercase (`tr '[:upper:]' '[:lower:]'`).
- Non-alphanumeric runs → single `-` (`sed -E 's/[^a-z0-9]+/-/g'`).
- Trim leading/trailing `-` (`sed -E 's/^-+//; s/-+$//'`).
- Cap at 40 chars (`cut -c1-40`).
- Trim trailing `-` again (`sed -E 's/-+$//'`) — catches boundary-after-cut case.

Worked examples (these are the contract — Phase 1 tests must match):

| Input | Slug |
|-------|------|
| `Fix README typo!` | `fix-readme-typo` |
| `Fix the broken link in docs/intro.md` | `fix-the-broken-link-in-docs-intro-md` |
| `  Update CHANGELOG  ` | `update-changelog` |
| `---Fix---foo---` | `fix-foo` |
| `This is a thirty-eight-char description X` *(41 chars total; cut falls after `X`, no trailing `-` produced)* | `this-is-a-thirty-eight-char-description` |
| `This is a thirty-nine-char description Y-` *(hypothetical trailing-`-` after cut)* | trailing-`-` trimmed by final sed |
| `!!!` (no alphanumerics) | `""` → exit 2 |

(R-L4: the previous example row claimed "trim-trailing-`-` applies" on an
input that wouldn't actually produce a trailing `-`. Corrected above to an
explicit trailing-`-` input.)

**Branch-name contract.**

| `--branch` value | config `branch_prefix` | Slug | Resulting BRANCH |
|------------------|------------------------|------|------------------|
| (absent) | (absent) | `fix-readme-typo` | `quickfix/fix-readme-typo` |
| (absent) | `"fix/"` | `fix-readme-typo` | `fix/fix-readme-typo` |
| (absent) | `""` | `fix-readme-typo` | `fix-readme-typo` (no prefix) |
| `custom/foo` | (any) | (any) | `custom/foo` (verbatim) |
| `feature-x` | (any) | (any) | `feature-x` |

**Push command contract.**

Always:
```
git push -u origin "$BRANCH"
```

Never use `HEAD:main`, never use `src:dst`, never use `--force`,
never use `--no-verify`. The bare-branch form routes around the latent
refspec bug in `block-unsafe-generic.sh:146` (DOC_PARTY_COMPARISON §3.1) and
is independently sound.

**Commit-message template (R2-M6 decision: mode-aware).**

**User-edited mode** (human authored the edits; /quickfix just ships them):

```
${DESCRIPTION}

🤖 Generated with /quickfix (user-edited)
```

**Agent-dispatched mode** (Claude-dispatched-agent authored the edits,
so attribution to Claude is semantically correct):

```
${DESCRIPTION}

🤖 Generated with /quickfix (agent-dispatched)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Rationale (R2-M6): round 1 chose blanket-omit with the rationale "user
or dispatched-agent authored, not Claude-the-tool." Round 2 flags the
asymmetry — in agent-dispatched mode, the dispatched agent IS Claude,
so the original rationale inverted for that mode. The refined
convention:

- In user-edited mode: NO `Co-Authored-By` (matches the user's intent
  — they authored the edits and ran /quickfix to ship them).
- In agent-dispatched mode: include `Co-Authored-By: Claude …` (the
  agent authored the edits; /quickfix orchestrated the commit).

The `(user-edited)` vs `(agent-dispatched)` suffix on the `/quickfix`
trailer lets `git log --grep` filter by mode cheaply. `/commit`
always includes `Co-Authored-By` (see `skills/commit/SKILL.md:204`);
/quickfix's mode-aware convention is a deliberate divergence
justified by the dual-mode design.

Implementation: WI 1.13 step 5's heredoc branches on `$MODE`:
```bash
if [ "$MODE" = "agent-dispatched" ]; then
  COMMIT_TRAILER=$'🤖 Generated with /quickfix (agent-dispatched)\n\nCo-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>'
else
  COMMIT_TRAILER='🤖 Generated with /quickfix (user-edited)'
fi
git commit -m "$(printf '%s\n\n%s\n' "$COMMIT_MSG" "$COMMIT_TRAILER")"
```

**Config reading — jq.** The plan reads config via `jq` (R-M11 correction):
`/do:309` already uses `jq`, so /quickfix inherits the same approach.
Rationale for `jq` over bash-regex: regex against JSON can mismatch on
embedded strings (e.g., key names appearing inside description fields or
`$schema` URLs — R-M8). `jq` is pinned as a hard pre-flight requirement
(WI 1.3).

**PR body template (verbatim — tests assert exact structure).** The body
lives in a `<<-EOF` heredoc (tab-stripped) inside the SKILL.md bash block,
so rendered output is:

```
## Summary
<description>

## Files changed
- <file1>
- <file2>
...
- DELETED: <deleted-file>   (if any)

## Test results
unit tests passed locally (<unit_cmd>)
<or: "tests skipped (--skip-tests)">

## How this PR was made
Shipped via /quickfix in <user-edited|agent-dispatched> mode.
```

Note: headings render at column 0 (no leading whitespace) because the body
inside `<<-EOF` has leading TABs which are stripped, not 4+ leading spaces
which would render as code (R-M1).

**Error messages (verbatim — tests assert substrings).**

| Code | Exact substring tests grep for |
|------|--------------------------------|
| 1 (jq)      | `requires \`jq\`` |
| 1 (gh)      | `requires the gh CLI` |
| 1 (landing) | `requires execution.landing == "pr"` |
| 1 (unit_cmd unset) | `requires testing.unit_cmd` |
| 1 (full-cmd mismatch) | `full_cmd differently from testing.unit_cmd` |
| 1 (branch)  | `must be invoked from main` |
| 1 (fetch)   | `git fetch origin` |
| 1 (parallel) | `another /quickfix appears to be in progress` |
| 2 (input)   | `needs either in-flight edits` |
| 2 (user-edited no description) | `user-edited mode requires a description` |
| 2 (branch-exists-local) | `already exists locally` |
| 2 (branch-exists-remote) | `exists on origin` |
| 2 (slug-empty)    | `could not derive slug` |
| 2 (slug-slash)    | `derived slug contains slash` |
| 4 (tests)   | `unit tests failed` |
| 5 (agent no-op)   | `agent returned but made no changes` |
| 5 (agent committed) | `sub-agent created a commit` |
| 5 (dir in changes) | `is a directory; feature-complete discipline` |
| 5 (commit)  | `git commit failed` |
| 5 (push)    | `git push failed` |
| 5 (pr)      | `gh pr create failed` |
| 6 (cleanup) | `cleanup:` (any cleanup-step failure — stderr names the failed git sub-command) |

**Test Cases (≥35, enumerated — each test must exit 0 on pass).**

1. **Config gate — cherry-pick rejected.** Config `landing: "cherry-pick"`;
   dirty tree; description → exit 1; stderr contains
   `requires execution.landing == "pr"`.
2. **Config gate — gh missing.** PATH stripped of `gh`; aligned config →
   exit 1; stderr contains `requires the gh CLI`.
3. **Branch guard — not on main.** Checked out on `feat/foo`; description →
   exit 1; stderr contains `must be invoked from main`.
4. **User-edited mode — happy path.** Dirty tree with 1 modified file;
   description `"Fix typo"`; mock `gh` returns a fake URL; `--yes` → exit 0;
   branch `quickfix/fix-typo` exists; 1 commit on branch; PR URL printed.
5. **Agent-dispatched mode — happy path.** Clean tree; description
   `"Add flag X"`; mock agent (shim script that touches a file) →
   exit 0; branch `quickfix/add-flag-x` exists; 1 commit.
6. **Both modes refused — no input.** Clean tree; empty description → exit 2;
   stderr contains `needs either in-flight edits`.
7. **Test failure cleanup.** Dirty tree; unit_cmd `false` → exit 4; branch
   `quickfix/*` does NOT exist after cleanup; working tree still dirty.
8. **Slug derivation.** Description `"Fix README typo!"` → branch is exactly
   `quickfix/fix-readme-typo`.
9. **Config branch_prefix.** Config `branch_prefix: "fix/"`; description
   `"Fix README typo"` → branch is exactly `fix/fix-readme-typo`.
10. **`--branch` override.** Description `"whatever"`; flag
    `--branch custom/foo` → branch is exactly `custom/foo` (prefix ignored).
11. **Push refspec safety (structural).** `grep -E 'git push [^|]*:'
    skills/quickfix/SKILL.md` must find NO matches (i.e., no
    `src:dst` refspec form anywhere in the skill source). R-M12: structural
    grep rather than runtime shim of `git`.
12. **No `.landed` marker.** After a successful run,
    `test ! -e "$MAIN_ROOT/.landed"` AND no `.landed` exists anywhere under
    `$MAIN_ROOT` (shell glob).
13. **User cancels confirmation.** Dirty tree; stdin replies `n` (no
    `--yes`) → exit 0; branch does NOT exist; tree still dirty.
14. **Run-all registration.** `grep -c 'test-quickfix.sh' tests/run-all.sh`
    is `≥ 1`.
15. **Agent no-op detection.** Clean tree + description; mock agent exits
    without modifying → exit 5; stderr contains `agent returned but made no
    changes`; branch cleaned up.
16. **Empty `branch_prefix`.** Config `branch_prefix: ""`; description
    `"Fix typo"` → branch is exactly `fix-typo` (bare slug, no prefix).
17. **Concurrent invocation refused.** Pre-write
    `.zskills/tracking/quickfix.other/fulfilled.quickfix.other` with
    `status: started`; invoke /quickfix → exit 1; stderr contains
    `another /quickfix appears to be in progress`.
18. **`full_cmd` mismatch rejected.** Config `unit_cmd: "a"`,
    `full_cmd: "b"`; dirty tree → exit 1; stderr contains `full_cmd
    differently from testing.unit_cmd`.
19. **`unit_cmd` unset rejected.** Config missing `testing.unit_cmd`;
    dirty tree → exit 1; stderr contains `requires testing.unit_cmd`.
20. **`--skip-tests` flag bypasses gate.** Config missing `testing.unit_cmd`;
    dirty tree; `--skip-tests --yes` → exit 0 (PR created; WARNING printed).
21. **Path with space handled.** Dirty tree with a file named
    `docs/my file.md`; description `"Fix doc"` → exit 0; commit touches
    exactly that file.
22. **Untracked file included.** Dirty tree: one untracked new file;
    description → exit 0; file is in the commit.
23. **Agent commits unexpectedly (sanity check).** Mock agent that creates a
    commit → exit 5; stderr contains `sub-agent created a commit`.
24. **User-edited without description.** Dirty tree; empty description →
    exit 2; stderr contains `user-edited mode requires a description`.
25. **Remote branch collision.** Local branch absent, remote origin has
    `quickfix/fix-typo`; dirty tree + matching description → exit 2; stderr
    contains `exists on origin`.

**Added in round 2 (Phase 1b test cases — all exit 0 on pass):**

26. **Stale parallel-invocation marker (R2-M5).** Pre-write
    `.zskills/tracking/quickfix.foo/fulfilled.quickfix.foo` with
    `status: started` and `date:` set to 2 hours in the past; invoke
    /quickfix with a fresh description → exit 0 (PR created) with stderr
    containing `stale`.
27. **Cancel writes `status: cancelled` (R2-M1).** Dirty tree; stdin `n`;
    no `--yes` → exit 0; marker file contains `status: cancelled` (NOT
    `status: complete`); branch deleted; tree still dirty.
28. **Cleanup-failure exit 6 (R2-H2).** Shim that makes `git branch -D`
    fail (e.g., return 1 unconditionally); force a test-failure path
    (`unit_cmd: "false"`) → exit 6; stderr contains `cleanup:`. The test
    harness restores the shim afterward.
29. **Agent-dispatched mode includes Co-Authored-By (R2-M6).** Mock
    agent shim that edits a file; run in agent-dispatched mode → commit
    message contains `Co-Authored-By: Claude` AND
    `🤖 Generated with /quickfix (agent-dispatched)`.
30. **User-edited mode omits Co-Authored-By (R2-M6).** Dirty tree;
    description; `--yes` → commit message contains
    `🤖 Generated with /quickfix (user-edited)` but NOT `Co-Authored-By`.
31. **Self-assertion catches missing `disable-model-invocation` (R2-L2).**
    Write a SKILL.md without the key; invoke skill → exit 1; stderr
    contains `missing 'disable-model-invocation: true'`.
32. **Remote-ref `ls-remote` failure is distinct from absent (R2-M4).**
    Point `origin` at an unreachable URL (e.g., `http://127.0.0.1:1/`);
    dirty tree → exit 1; stderr contains `git ls-remote origin failed`
    (NOT `exists on origin`).
33. **Mirror uses literal-path idiom (R2-H1 structural).**
    `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md` produces no output.
    (Structural guard; complements test case 11 / 12 / 14.)
34. **No `|| true` in skill source (R2-H2 structural).**
    `grep -nE '\|\| true' skills/quickfix/SKILL.md` produces no output.
35. **DIRTY_AFTER excludes untracked (R2-M2).** Agent-dispatched mode;
    mock agent shim that edits a tracked file AND also writes an
    untracked `coverage/report.html`; invoke → commit includes only the
    tracked edit; `coverage/report.html` is NOT in the commit
    (untracked files from agent are ignored by the DIRTY_AFTER check).

Test case count: **35** (was 25 after round 1; 10 added in round 2).
Phase 1a covers cases 1–10 + registration (14). Phase 1b covers
cases 11–25 (edge cases) + 26–35 (round-2 additions) = 25.
Tests 11, 12, 14, 33, 34 are structural/guard tests; the rest are
functional.

**Mock `gh` wrapper.** Create a script on PATH that handles `gh pr create`
(returns a fake URL on stdout, rc 0) and delegates anything else to a stub.
The test harness exports `PATH=$TESTDIR/mock:$PATH` in each case. This
mirrors the pattern in `tests/test-hooks.sh` for mocked CLIs.

**Tracking contract.**

- PIPELINE_ID: `quickfix.<slug>` (after sanitization).
- Markers written:
  - `$MAIN_ROOT/.zskills/tracking/$PIPELINE_ID/fulfilled.quickfix.<slug>` —
    status transitions `started` → `complete` (normal) or `started` → `failed`
    (abnormal exit). Successful runs append `pr: <URL>`.
- Transcript echoes `ZSKILLS_PIPELINE_ID=<pipeline>` at skill entry for
  tier-2 tracking association (same pattern as `tests/test-hooks.sh:245`).
- No step markers (single-skill flow; no Phase 2/3/4 breakdown to track).
- No `.landed` marker.

### Acceptance Criteria (Phase 1b)

Phase 1b inherits all Phase 1a acceptance criteria and ADDS the
following. After 1b, the full 25-case suite passes.

- [ ] `bash tests/test-quickfix.sh` exits 0 and prints a
  `Results: N passed, 0 failed` line with N ≥ 35 (25 from round 1
  + 10 added in round 2).
- [ ] `bash tests/run-all.sh` exits 0 (overall suite remains green with
  quickfix registered).
- [ ] `diff -r skills/quickfix .claude/skills/quickfix` produces no output
  (mirror is byte-identical — R2-H1 literal-form idiom verified).
- [ ] **R2-H1:** `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md`
  produces NO output (no variable-containing `rm -rf` anywhere).
- [ ] **R2-H2:** `grep -nE '\|\| true' skills/quickfix/SKILL.md`
  produces NO output (no `|| true` suppression anywhere).
- [ ] **R2-H2 (exit-6):** The skill source defines exit code 6 for
  cleanup failures; `grep -q 'exit 6' skills/quickfix/SKILL.md` succeeds.
- [ ] **R2-M1:** `grep -q 'status: cancelled' skills/quickfix/SKILL.md`
  succeeds (explicit cancelled terminal state).
- [ ] **R2-M5:** `grep -q 'stale' skills/quickfix/SKILL.md` succeeds and
  the parallel-invocation gate compares marker `date` against current
  time (staleness detection in WI 1.3.5).
- [ ] **R2-L2:** `grep -q 'disable-model-invocation' skills/quickfix/SKILL.md`
  succeeds AND the skill's entry bash contains a self-assertion that
  greps its own SKILL.md for the key and fails loudly if absent.
- [ ] `grep -qE 'HEAD:main|HEAD:master' skills/quickfix/SKILL.md` **FAILS**.
- [ ] `grep -q -- '--no-verify' skills/quickfix/SKILL.md` **FAILS**.
- [ ] `grep -qE '(write|cat >).*\.landed' skills/quickfix/SKILL.md` **FAILS**.
- [ ] `grep -E 'git push [^|]*:' skills/quickfix/SKILL.md` produces no
  output (structural R-M12).
- [ ] `grep -q 'sanitize-pipeline-id.sh' skills/quickfix/SKILL.md` succeeds.
- [ ] `grep -q 'PIPELINE_ID' skills/quickfix/SKILL.md` succeeds.
- [ ] `grep -q '/tmp/zskills-tests' skills/quickfix/SKILL.md` succeeds.
- [ ] `grep -qE 'merge --ff-only' skills/quickfix/SKILL.md` **FAILS**.

### Dependencies (Phase 1b)

Phase 1b depends on Phase 1a (edits the same skill-source file).
Consumes the same existing infrastructure as 1a. Does NOT require
Phase 3 to land.

---

## Phase 3 — Documentation and Cross-Skill Notes

### Goal

Make `/quickfix` visible to users and to other zskills that enumerate skills.
Every update is a targeted doc edit with a grep-verifiable outcome.

### Work Items

- [ ] 3.1 — `CLAUDE_TEMPLATE.md` PR-workflow section. Current state (verified
      by `grep -n '/do Add dark mode' CLAUDE_TEMPLATE.md`) — line 153 reads:
      ```
      - `/do Add dark mode. pr`
      ```
      Add a new bullet immediately before that line:
      ```
      - `/quickfix Fix README typo` — low-ceremony PR for trivial changes (no worktree; picks up in-flight edits in main)
      ```
      Acceptance: `grep -q 'quickfix Fix README typo' CLAUDE_TEMPLATE.md`.

- [ ] 3.2 — `DOC_PARTY_COMPARISON.md §4.1` status note. Current state
      (line 243, `### 4.1 \`/quickfix\` skill`) describes the gap as a
      recommendation. Replace §4.1's body to add a "Status" line at the top:
      ```markdown
      ### 4.1 `/quickfix` skill

      **Status:** Shipped — see `skills/quickfix/SKILL.md` (landed
      via `plans/QUICKFIX_SKILL.md`).

      Generic branch-from-main + commit + PR for trivial changes (typos, one-line
      fixes) where spinning up a worktree and `npm install` is disproportionate.
      Useful in any project that uses PR mode. Low implementation cost.
      ```
      Acceptance: `grep -q 'Shipped — see .skills/quickfix' DOC_PARTY_COMPARISON.md`.

- [ ] 3.3 — Register `/quickfix` in `skills/update-zskills/SKILL.md`.
      **R2-L1 protocol: read the current count first, then increment by
      one.** The current anchor line (verified today at line 32) reads
      `"Without an add-on flag, only the 17 core skills are installed/updated."`
      but this phrase may have been updated between plan-draft and
      plan-execution. Do NOT hardcode `17 → 18`. Instead:
      ```bash
      # Read the current count — fail loudly if not found or ambiguous
      CURRENT_COUNT=$(grep -oE 'only the [0-9]+ core skills are installed' \
        skills/update-zskills/SKILL.md | grep -oE '[0-9]+' | head -1)
      if [ -z "$CURRENT_COUNT" ]; then
        echo "ERROR: could not find 'only the N core skills are installed' in update-zskills/SKILL.md. Locate the canonical count phrase manually and update by +1." >&2
        exit 1
      fi
      NEW_COUNT=$((CURRENT_COUNT + 1))
      echo "Updating core-skill count: $CURRENT_COUNT -> $NEW_COUNT"
      # Edit the line to use $NEW_COUNT
      ```
      Rationale: research today shows `skills/` has 18 subdirectories but
      update-zskills:32 says "17 core skills." `manual-testing/` is not
      currently in update-zskills's core-skill enumeration (confirmed by
      grep). After `/quickfix`, the count becomes (CURRENT + 1) — the
      increment is correct regardless of whether `CURRENT` was 17
      (today's value) or has drifted since.

      Also add `/quickfix` to any enumerated skill list. Run:
      ```bash
      grep -n -E '/commit|/do |/run-plan|core skill' skills/update-zskills/SKILL.md | head -20
      ```
      to locate any additional mentions. If there is no single enumerated
      list, this work item acknowledges the grep-first fallback.
      Acceptance: `grep -q 'quickfix' skills/update-zskills/SKILL.md` AND
      `grep -qE "${NEW_COUNT} core skill" skills/update-zskills/SKILL.md`
      (where `$NEW_COUNT` is the computed value above).

- [ ] 3.4 — `README.md` skill list. Current state (verified):
      `#### Ship` section at line 106 contains only `/commit` and
      `/briefing`. Insert `/quickfix` between them:
      ```
      | `/quickfix` | Low-ceremony PR from main: picks up in-flight edits (or agent-dispatches), no worktree, fire-and-forget CI |
      ```
      (`grep -n 'core skill' README.md` finds no count phrase to update,
      so no count edit is needed — unlike update-zskills.)
      Acceptance: `grep -q '\`/quickfix\`' README.md` AND the quickfix row
      appears within the `#### Ship` table
      (`grep -A 10 '#### Ship' README.md | grep quickfix`).

- [ ] 3.5 — Mirror any skill source edits. After 3.3, re-mirror
      `skills/update-zskills/` to `.claude/skills/update-zskills/`.
      (Same literal-path idiom as Phase 1b WI 1.19 — R2-H1.)
      ```bash
      cd "$MAIN_ROOT" && rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/update-zskills
      diff -r skills/update-zskills .claude/skills/update-zskills
      ```
      Acceptance: `diff -r` produces no output.

### Design & Constraints

**CLAUDE_TEMPLATE.md insertion — diff spec.**

```diff
 **Usage:** Append keyword to any execution skill:
 - `/run-plan plans/X.md finish auto pr`
 - `/fix-issues 10 pr`
 - `/research-and-go Build an RPG. pr`
+- `/quickfix Fix README typo` — low-ceremony PR for trivial changes (no worktree; picks up in-flight edits in main)
 - `/do Add dark mode. pr`
```

**DOC_PARTY_COMPARISON.md §4.1 — diff spec.**

```diff
 ### 4.1 `/quickfix` skill

+**Status:** Shipped — see `skills/quickfix/SKILL.md` (landed
+via `plans/QUICKFIX_SKILL.md`).
+
 Generic branch-from-main + commit + PR for trivial changes (typos, one-line
 fixes) where spinning up a worktree and `npm install` is disproportionate.
 Useful in any project that uses PR mode. Low implementation cost.
```

**README.md `#### Ship` insertion — diff spec.**

```diff
 #### Ship

 | Skill | Purpose |
 |-------|---------|
 | `/commit` | Safe commit: scope classification, import tracing, fresh review agent, dependency verification |
+| `/quickfix` | Low-ceremony PR from main: picks up in-flight edits (or agent-dispatches), no worktree, fire-and-forget CI |
 | `/briefing` | Project status dashboard: recent commits, worktree status, pending sign-offs |
```

**update-zskills skill-list update — locate-then-edit (R-L2 + R2-L1).**

Anchor: the line matching `only the [0-9]+ core skills are installed`
(today at line 32, value `17`). Read CURRENT_COUNT at run time;
increment by 1. Do NOT hardcode the count — `manual-testing/` exists as
a directory but is not in update-zskills's enumeration, so the raw
`ls skills/` count diverges from update-zskills's claim. The correct
operation is always `CURRENT + 1`, regardless of what CURRENT is.

### Acceptance Criteria (Phase 3)

- [ ] `grep -q 'quickfix Fix README typo' CLAUDE_TEMPLATE.md` succeeds.
- [ ] `grep -q 'Shipped — see' DOC_PARTY_COMPARISON.md` succeeds on the
  §4.1 line AND that section header `### 4.1 \`/quickfix\` skill` is still
  present (don't accidentally restructure).
- [ ] `grep -q '\`/quickfix\`' README.md` succeeds AND appears in the
  `#### Ship` table (verify by context:
  `grep -A 10 '#### Ship' README.md | grep quickfix`).
- [ ] `grep -q 'quickfix' skills/update-zskills/SKILL.md` succeeds.
- [ ] The core-skills count in `update-zskills/SKILL.md` is exactly
  CURRENT+1 where CURRENT was read by the WI 3.3 shell block. (Example
  today: `grep -qE '18 core skill' skills/update-zskills/SKILL.md`.)
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills`
  produces no output.
- [ ] `bash tests/run-all.sh` still exits 0 (no test regressed from doc
  edits).

### Dependencies (Phase 3)

Phase 3 depends on Phase 1a AND Phase 1b (the skill source must exist
AND be hardened before we document it). Phase 3 adds no new tests.

---

## Plan Quality

*Filled in after adversarial review rounds. Initial draft populated by the
Phase 2 drafter; reviewer + devil's advocate to follow.*

**Drafting process:** `/draft-plan` with N rounds of adversarial review
**Convergence:** [to be filled by Phase 5]
**Remaining concerns:** [to be filled by Phase 5]

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 15                | 9 (24 total, 8H/12M/5L)   | 24       |
| 2     | combined          | 11 (3H/6M/2L)             | 11       |
| 3     | combined          | 8 (0H/1M/7L; polish only) | applied inline |

---

## Round 1 Disposition

24 findings from `/tmp/draft-plan-review-QUICKFIX_SKILL-round-1.md`.
Evidence verified against working tree; each row shows independent
reproduction or explicit judgment.

| ID | Severity | Evidence | Disposition | Notes |
|----|----------|----------|-------------|-------|
| R-H1 | HIGH | Verified — `hooks/block-unsafe-project.sh.template:188-229` confirms transcript-based `FULL_TEST_CMD` check on `git commit` with staged code files. Plan's `unit_cmd`-only stance conflicts. | Fixed | WI 1.3 check 4 adds the test-cmd alignment gate: `unit_cmd` must be set AND (`full_cmd` unset OR `full_cmd == unit_cmd`). Otherwise hard-error rc=1 with guidance to align config or use `/commit pr` / `/do pr`. Test cases 18–20 cover the gate. Acceptance criterion added: `grep -q 'full_cmd' skills/quickfix/SKILL.md`. |
| R-H2 | HIGH | Verified — WI 1.9 (rc=2 on branch exists) contradicts WI 1.13 step 6 (branch reused) contradicts research Q6. | Fixed | Option (b) adopted: on commit failure, WI 1.13 step 5 auto-cleans (checkout `$BASE_BRANCH`, delete branch, unstaged edits return to tree). User fixes root cause and re-runs from clean slate. WI 1.9 remains strict. Narrative updated throughout. |
| R-H3 | HIGH | Verified — `skills/do/SKILL.md:342-358` is the same pattern; MEMORY `project_subagent_architecture.md` confirms cannot dispatch from bash. | Fixed | WI 1.11 now explicitly marked "model-layer instruction, not bash." Success detection: `git status --porcelain` non-empty AND HEAD unchanged (via `PRE_HEAD`/`POST_HEAD` compare). `ZSKILLS_PIPELINE_ID=quickfix.$SLUG` echoed at WI 1.8 for tier-2 tracking. Sub-agent explicitly told not to commit; post-dispatch HEAD check aborts if it did. Timeout out of scope for v1 noted. |
| R-H4 | HIGH | Verified — `grep -n 'flock\|lock\|concurrent' plans/QUICKFIX_SKILL.md` returns 0; MEMORY `feedback_parallel_pipelines_core.md` confirms this is core. | Fixed | WI 1.3.5 added: scan `.zskills/tracking/quickfix.*/fulfilled.quickfix.*` for `status: started`; exit 1 if found. WI 1.8 writes started-marker and installs an EXIT trap finalizing to `complete` or `failed`. TEST_OUT now includes slug: `/tmp/zskills-tests/$(basename "$MAIN_ROOT")-quickfix-$SLUG` (WI 1.12). Test case 17 added for concurrent refusal. |
| R-H5 | HIGH | Verified — `git merge --ff-only` refuses when dirty-tree paths overlap upstream changes; this is standard git semantics. | Fixed | WI 1.4 drops the ff-merge entirely; only `git fetch origin "$BASE_BRANCH"`. WI 1.9 uses `git checkout -b "$BRANCH" "origin/$BASE_BRANCH"` which branches from the remote ref and carries the dirty tree. `gh pr create --base "$BASE_BRANCH"` handles divergence. Acceptance criterion added: `grep -qE 'merge --ff-only' skills/quickfix/SKILL.md` **FAILS**. |
| R-H6 | HIGH | Verified — git porcelain v1 emits `XY orig -> path` for renames, quoted paths with escapes for special chars; naive column-strip breaks. | Fixed | WI 1.10 step 1 replaces the naive parse: `git diff --name-only HEAD` (mods+renames, new-path form) + `git ls-files --others --exclude-standard` (untracked) + `git diff --name-only --diff-filter=D HEAD` (deletions). WI 1.13 stages with `git add -- "${CHANGED_FILES[@]}"` and `git add -u -- "${DELS[@]}"`. Test cases 21 (path with space) and 22 (untracked file) added. Untracked files documented as included in /quickfix's change set. |
| R-H7 | HIGH | Verified — WI 1.12 in the original plan explicitly warn-and-skipped on empty `unit_cmd`. | Fixed | WI 1.3 check 4 hard-errors if `unit_cmd` unset (unless `--skip-tests`). `--skip-tests` flag added to argument grammar and documented. Pairs with R-H1 fix. Test cases 19 (unit_cmd unset rejected) and 20 (`--skip-tests` bypass) added. |
| R-H8 | HIGH | Verified — `git show-ref --verify --quiet refs/heads/X` exits non-zero when only `refs/remotes/origin/X` exists. Standard git ref semantics. | Fixed | WI 1.9 step 2 adds remote check: `git fetch origin "$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null || true` then `git show-ref --verify --quiet refs/remotes/origin/$BRANCH`. If exists, exit 2 with cleanup guidance (`git push origin --delete $BRANCH` or `--branch <other>`). Test case 25 covers remote collision. |
| R-M1 | MEDIUM | Verified by inspection — original WI 1.15 heredoc used `<<EOF` with 6-space indentation in the SKILL.md bash block; markdown interprets 4+ spaces as code block, breaking headings. | Fixed | WI 1.15 switched to `<<-EOF` with TAB-prefixed body (tabs stripped by `<<-`); heading lines render at column 0. Explicit note added that the SKILL.md body MUST use tabs, not spaces. |
| R-M2 | MEDIUM | Verified — POSIX: `$(cmd)` strips trailing newlines. `printf -- '- %s\n' "$@"` also mis-parses format specifiers when filenames contain `%`. | Fixed | WI 1.15 uses `$({ printf '%s\n' "${CHANGED_FILES[@]/#/- }"; echo; })` — the `; echo` adds a sentinel newline; `printf '%s\n'` with a single format token avoids injection. |
| R-M3 | MEDIUM | Verified — original WI 1.4 accepts `main`/`master`; original WI 1.15 hardcoded `--base main`. Mismatch on master-default repos. | Fixed | WI 1.4 captures `BASE_BRANCH="$CURRENT_BRANCH"`; WI 1.15 uses `--base "$BASE_BRANCH"`. Same variable used for `git fetch`, `git checkout -b ... "origin/$BASE_BRANCH"`, cleanup paths. |
| R-M4 | MEDIUM | Judgment — on-main guard may block legitimate integration-branch workflows; not reproduced since we added the flag. | Fixed | `--from-here` flag added in WI 1.2; WI 1.4 skips the branch guard when set. Documented in argument grammar. |
| R-M5 | MEDIUM | Verified — original WI 1.13 step 4 derived `quickfix: update <basename>` when DESCRIPTION empty. Weak. | Fixed | DESCRIPTION is now required in user-edited mode (WI 1.5 rejection clause). Slug derivation simplified (no "first changed file" fallback). Test case 24 added. |
| R-M6 | MEDIUM | Verified — `tests/test-hooks.sh:226-254` `setup_project_test()` is the precedent. Original WI 1.17 was underspecified. | Fixed | Added explicit "Test harness isolation" block in Design & Constraints: per-case `mktemp -d`, cd, mock `.claude/zskills-config.json` with aligned `unit_cmd`/`full_cmd`, mock `gh` on PATH, `trap RETURN` cleanup. References the `setup_project_test()` pattern. |
| R-M7 | MEDIUM | Verified — `read` would block CI. No non-interactive flag in the original. | Fixed | `--yes`/`-y` flag added to argument grammar (WI 1.2); WI 1.10 step 3 skips prompt when set. Test 4 uses `--yes`; test 13 exercises the interactive path. |
| R-M8 | MEDIUM | Verified — bash regex against JSON can match inside string values (e.g., `$schema` URL, description fields). `jq` is available (`which jq` → `/usr/bin/jq`). | Fixed | All config reads switched to `jq` in WI 1.3 and 1.7. `jq` added to pre-flight dependency check. Narrative in Design & Constraints corrected. |
| R-M9 | MEDIUM | Verified — `git add foo.txt` with `foo.txt` starting with `-` interprets as flag; directories recurse. | Fixed | WI 1.13 step 3 uses `git add -- "${CHANGED_FILES[@]}"` (`--` separator) and rejects directory entries with exit 5 before staging. |
| R-M10 | MEDIUM | Verified — no WI references exit code 3 in the original plan. | Fixed | Exit code 3 removed from the exit-codes table. |
| R-M11 | MEDIUM | Verified — `skills/commit/SKILL.md:204` DOES include `Co-Authored-By`; `skills/do/SKILL.md:309` uses `jq`. Original rationales inverted both. | Fixed | Commit-message rationale rewritten: /quickfix's omission of `Co-Authored-By` is a deliberate divergence from `/commit`, justified (user/agent authored the change). jq rationale rewritten: /quickfix matches `/do`'s jq approach for correctness vs regex brittleness. |
| R-M12 | MEDIUM | Verified — replacing `git` affects all git calls in /quickfix, making shim-based test brittle. | Fixed | Test case 11 is structural: `grep -E 'git push [^|]*:' skills/quickfix/SKILL.md` must find no matches. Matches the existing test-12 (`.landed`) pattern. Acceptance criterion added. |
| R-L1 | LOW | Verified — no empty-`branch_prefix` test case in the original. | Fixed | Test case 16 added: `branch_prefix: ""` → bare-slug branch. |
| R-L2 | LOW | Verified — `grep -n '17 core' skills/update-zskills/SKILL.md` returns line 32. | Fixed | WI 2.3 pins line 32 as the canonical update anchor and describes the grep-first fallback for any additional references. |
| R-L3 | LOW | Verified — `grep 'rm -rf .claude/skills/' plans/*.md` shows the idiom used repeatedly in `plans/RESTRUCTURE_RUN_PLAN.md`, `plans/CREATE_WORKTREE_SKILL.md`, `plans/FIX_PR_STATE_RATE_LIMIT.md`. Hook's `is_safe_destruct` in `hooks/block-unsafe-generic.sh:113-126` requires a literal `/tmp/<name>` path AND no variables/globs — a concrete `.claude/skills/<name>` path is NOT in `/tmp/` so the `is_safe_destruct` branch doesn't apply; the `RM_RECURSIVE` block only triggers when `is_safe_destruct` would otherwise gate it. Re-reading lines 128-134: `rm -r` *is* gated by `is_safe_destruct`, which fails for non-`/tmp/` paths — so theoretically the hook could block. But empirical evidence (recurring use in other plans with no reported issue) suggests it passes; most likely because the hook's regex anchors on the `rm` invocation form and the plans run `rm -rf "$MAIN_ROOT/.claude/skills/<name>"` where `$MAIN_ROOT` expands to the actual path. | Fixed | WI 1.19 adopts the exact idiom from `plans/RESTRUCTURE_RUN_PLAN.md`: `rm -rf "$MAIN_ROOT/.claude/skills/quickfix" && cp -r "$MAIN_ROOT/skills/quickfix" "$MAIN_ROOT/.claude/skills/quickfix"`. Work Item includes a note explaining the precedent and the safety rationale. If Round 2 re-verification shows the hook DOES block, fallback is `rm -rf /tmp/zskills-mirror-staging && cp -r ... /tmp/zskills-mirror-staging && mv ...` — but empirical precedent suggests this isn't needed. |
| R-L4 | LOW | Verified by inspection — original line 496 example `foo bar *(and cut falls on -bar)*` is self-contradictory. | Fixed | Slug examples table rewritten with accurate trailing-`-` hit: `---Fix---foo---` → `fix-foo` (leading/trailing trimmed); hypothetical 41-char boundary example clarified. |
| R-L5 | LOW | Verified — `grep -n 'disable-model-invocation' skills/*/SKILL.md` shows 12 existing SKILL.md files use the key (including `/commit`, `/do`, `/fix-issues`, `/fix-report`, `/qe-audit`, `/doc`, `/plans`, `/investigate`, `/draft-plan`, `/refine-plan`, `/run-plan`, `/verify-changes`). | Fixed | WI 1.1 retains `disable-model-invocation: true`; rationale updated to "verified against 12 existing SKILL.md files in zskills" (was previously "matches /commit and /do"). |

### Disposition Summary

- **Fixed:** 24
- **Justified (no change needed):** 0
- **Plan-killer R-H1:** Fixed via pre-flight test-cmd alignment gate.
- **Plan-killer R-H5:** Fixed by dropping ff-merge, branching from `origin/$BASE_BRANCH`.

### Judgment Calls

1. **R-H1 option (c)** chosen per review guidance: hard-error on
   `full_cmd != unit_cmd` rather than patching the hook or echoing a
   marker. Simplest. Users opt in by aligning their config or using
   `/commit pr`. Alternative options (a)/(b)/(d) noted in R-H1 but not
   adopted.
2. **R-H2 option (b)** chosen per review guidance: auto-cleanup on commit
   failure (checkout base, delete branch, edits persist). Alternative (a)
   — "allow WI 1.9 reuse if HEAD already points to branch AND no commits
   ahead of main" — was rejected as more surprising. Option (b) is
   "always clean re-run."
3. **Commit message `Co-Authored-By`** — kept omitted. Divergence from
   `/commit` is deliberate (user/agent authored, not Claude-the-tool).
   Narrative corrected.
4. **Config reader** — switched from bash-regex to `jq`. `jq` added as a
   hard dependency. Matches `/do` precedent.
5. **R-L3 mirror idiom** — kept as-is with empirical precedent from other
   plans. Round 2 should re-verify by dry-run if any doubt remains.
6. **Test case count** — raised from 15 to 25 to cover new gates. ≥15
   requirement still met with slack.
7. **Pre-flight Config check ordering** — moved jq/gh checks before
   landing check so the error message is "install jq" rather than a
   bash-parse failure when jq is missing.

### Convergence Assessment (Round 1)

**Round 1 self-assessed "converged" but this was WRONG.** Round 2
review found 3 new HIGHs that round-1 refinement introduced or left
unaddressed (see Round 2 Disposition below):

- **R2-H1:** R-L3's mirror fix (`rm -rf "$MAIN_ROOT/..."`) was
  live-reproduced as hook-blocked in round 2. Round 1 made a judgment
  call citing "empirical precedent" but the precedent plans use the
  LITERAL form (no `$`); round 1 conflated them.
- **R2-H2:** R-H2 and R-H3 cleanup refinements introduced `|| true`
  suppression in at least four locations — directly violating
  CLAUDE.md's "Never suppress errors on operations you need to verify."
- **R2-H3:** Phase 1 grew to 20 WIs + 25 tests; too large to be
  reliably shippable in one phase.

Lesson for future refiners: a round that adds cleanup paths or
destructive operations must specifically re-verify those additions
against the live hook set and the CLAUDE.md rules. Round 1 did not.

Round 2 addresses all three HIGHs plus 6 MEDIUMs and 2 LOWs.

---

## Round 2 Disposition

11 findings from `/tmp/draft-plan-review-QUICKFIX_SKILL-round-2.md` (3
HIGH / 6 MEDIUM / 2 LOW). Each finding re-verified against the
working tree and the live hook set; evidence independently reproduced.

| ID | Severity | Evidence | Disposition | Notes |
|----|----------|----------|-------------|-------|
| R2-H1 | HIGH | **Live-reproduced in this round**: a Bash tool call containing `rm -rf` was blocked verbatim by `block-unsafe-generic.sh` with `is_safe_destruct` — confirming the hook rejects any `rm -r[f]` that contains `$` (even if the containing command is a grep). Read `hooks/block-unsafe-generic.sh:113-134` — `is_safe_destruct` returns false for any command with `$`, backtick, `*`, `?`, or leading `~`, AND requires literal `/tmp/<name>` to pass. So `rm -rf "$MAIN_ROOT/.claude/skills/quickfix"` fails both checks. Read `plans/RESTRUCTURE_RUN_PLAN.md:184,328,491,805,810` — all precedent mirrors use the LITERAL form `rm -rf .claude/skills/<name>` after `cd`. Read plan WI 2.5 (now WI 3.5) — already uses the literal idiom correctly. | Fixed | WI 1.19 rewritten to `cd "$MAIN_ROOT" && rm -rf .claude/skills/quickfix && cp -r skills/quickfix .claude/skills/quickfix` (literal path, no `$` on the `rm` line). Acceptance criterion added (Phase 1b): `grep -E 'rm -rf "\$' skills/quickfix/SKILL.md` returns NO matches. Structural test case 33 added. WI 3.5 (renumbered from 2.5) also uses the literal idiom. Rationale expanded in WI 1.19 body explaining hook semantics.
| R2-H2 | HIGH | Verified — grep `\\|\\| true` in plan found 8 matches across WI 1.9 step 2 (line 306), WI 1.11 step 4 (lines 405-407), WI 1.13 step 3 directory-reject (lines 462-463), WI 1.13 step 5 (lines 496-498). CLAUDE.md rule: "Never suppress errors on operations you need to verify." MEMORY `feedback_or_true_pattern.md`: "\\|\\| true pattern is almost never correct." | Fixed | All 8 `\\|\\| true` instances replaced with `if ! <cmd>; then <report> exit 6; fi` patterns. New exit code 6 added: "cleanup failure (manual intervention needed)," distinct from code 5 (operation failure) so the user can see whether rollback worked. Exit-codes table updated. Error-message table updated to add `cleanup:` substring. Acceptance criterion: `grep -nE '\\|\\| true' skills/quickfix/SKILL.md` returns NO matches. Structural test case 34 added. Plus R2-M4 (WI 1.9 step 2) switched to `git ls-remote` (see that row).
| R2-H3 | HIGH | Verified — `grep -c '^- \\[ \\] 1\\.' plan` before round 2: 20 WIs in Phase 1 (1.1-1.19 + 1.3.5). Test cases enumerated 1-25. Research §7 target was ≥10 / ~12. | Fixed | Phase 1 split into **Phase 1a (WIs 1.1-1.15 + 1.3.5; tests 1-10 + 14)** and **Phase 1b (WIs 1.16-1.19; tests 11-25 + 26-35)**. Phase 2 renumbered to **Phase 3**; its WIs renumbered from 2.x → 3.x. Progress Tracker updated with 3 rows. Dependencies updated (1b depends on 1a; 3 depends on 1a AND 1b). Phase-split rationale section added to Progress Tracker. Phase 1a ships a core-complete skill; Phase 1b hardens it. Runtime "Stage N" naming (inside SKILL.md) renamed from "Phase N" to avoid colliding with the plan's phase names.
| R2-M1 | MEDIUM | Verified — WI 1.10 step 3 cancel path: rc=0 → EXIT trap writes `status: complete`. WI 1.16 appends `pr:` on success. Cancel writes no `pr:`. So "cancel" and "success" are distinguished only by absence of `pr:` — an implicit convention. | Fixed | Introduced `CANCELLED=1` shell variable set by WI 1.10 step 3 cancel path; EXIT trap branches on `CANCELLED` → writes `status: cancelled` (new terminal state) instead of `status: complete`. WI 1.8 documents all four terminal states (`started`, `complete`, `cancelled`, `failed`) in the Tracking contract. Test case 27 added. Acceptance criterion added (Phase 1b): skill source contains `status: cancelled`.
| R2-M2 | MEDIUM | Verified — WI 1.11 step 4 `DIRTY_AFTER=$(git diff --name-only HEAD; git ls-files --others --exclude-standard)` — if agent writes coverage/build artifacts outside `.gitignore`, this triggers "agent made edits" false-positive. | Fixed | WI 1.11 step 3 agent prompt tightened: explicit instructions to NOT run tests/builds/linters/formatters. DIRTY_AFTER changed to `git diff --name-only HEAD` only (dropped `ls-files --others`). Limitation documented: agent-created new untracked files won't be auto-detected; agent must list them in "done" report. Test case 35 added (agent creates both tracked-edit and untracked file; commit includes only the tracked edit).
| R2-M3 | MEDIUM | Verified — 9+ pre-flight checks in WI 1.3, 1.3.5, 1.4; plan did not specify fail-fast vs enumerate. | Fixed | "Stage 0 — Pre-flight" description in Design & Constraints explicitly documents fail-fast: one error per run; a user fixing three issues re-runs three times. Rationale: matches `/do` and `/commit` idiom; simpler than multi-line enumeration.
| R2-M4 | MEDIUM | Verified — WI 1.9 step 2 used `git fetch origin "$BRANCH:refs/remotes/origin/$BRANCH" 2>/dev/null \\|\\| true` — same `\\|\\| true` antipattern plus the case conflation (branch absent vs network failure). | Fixed | Replaced with `LS_OUT=$(git ls-remote --heads origin "$BRANCH")` + explicit rc/output checks. Non-zero rc → exit 1 with "network/auth" message (distinct from "branch exists"). Empty output with rc=0 → branch absent, proceed. Non-empty output → exit 2 with cleanup guidance. Test case 32 added (unreachable origin → exit 1, not exit 2).
| R2-M5 | MEDIUM | Verified — WI 1.3.5 pre-round-2 checked `status: started` but had no time-based staleness check. SIGKILLed /quickfix leaves marker forever. | Fixed | WI 1.3.5 expanded with staleness detection: read marker's `date:` field, compare to current time; if `AGE > STALE_AGE_SECONDS` (default 3600 = 1h) print warning and proceed. `date -d` parses ISO-8601. Test case 26 added (2h-old `started` marker → exit 0 with stale warning).
| R2-M6 | MEDIUM | Verified — round-1 rationale "user/agent authored, not Claude-the-tool" is weak for agent-dispatched mode because the dispatched agent IS Claude. `/commit` includes Co-Authored-By at `skills/commit/SKILL.md:204`. | Fixed | Adopted **mode-aware convention**: agent-dispatched commits include `Co-Authored-By: Claude Opus 4.7 (1M context) …`; user-edited commits do not. Mode is also encoded in the trailer (`🤖 Generated with /quickfix (user-edited)` vs `(agent-dispatched)`). WI 1.13 step 5 branches on `$MODE`. Design & Constraints "Commit-message template" rewritten with both variants. Test cases 29 (agent-dispatched includes) and 30 (user-edited omits) added.
| R2-L1 | LOW | Verified — `grep core.skills skills/update-zskills/SKILL.md` shows line 32: "17 core skills". `skills/` has 18 directories including `manual-testing/`. `manual-testing` is not in update-zskills's enumeration — so 17 is today's canonical count; +1 = 18 (correct). | Fixed | WI 3.3 (renumbered from 2.3) reads CURRENT_COUNT at run time via `grep -oE 'only the [0-9]+ core skills are installed'` and increments. Hardcoded `17→18` replaced with dynamic `CURRENT+1`. Error path if the phrase is not found or ambiguous. Acceptance criterion references `NEW_COUNT` (computed), with today's value `18` shown as example.
| R2-L2 | LOW | Verified — `grep -l 'disable-model-invocation: true' skills/*/SKILL.md` returned 7 files (round-1's "12" was actually `skills/*/SKILL.md + .claude/skills/*/SKILL.md = 14`; round-1 inflated). The frontmatter key is a convention internal to zskills, not a schema-validated Anthropic key. If silently ignored, the skill auto-fires on keyword matches. | Fixed | WI 1.1 adds runtime self-assertion: at skill entry, `grep -q '^disable-model-invocation: true' "$SKILL_SELF"` (falling back to known install paths if `$0` is unusual); fail with exit 1 if missing. Test case 31 added (stripped-frontmatter SKILL.md → exit 1 with explicit error). Round-1's "12 files" claim corrected to "7 files" (re-verified in round 2 by `grep -l disable-model-invocation: true skills/*/SKILL.md`).

### Disposition Summary (Round 2)

- **Fixed:** 11 (all HIGHs, MEDIUMs, and LOWs addressed in plan text)
- **Justified (no change needed):** 0
- **Plan-killer R2-H1** (hook blocks mirror) — fixed via literal-path
  idiom matching WI 3.5; structural grep acceptance prevents regression.
- **Plan-killer R2-H2** (silenced cleanup errors) — fixed by purging
  `|| true` + introducing exit code 6; structural grep acceptance
  prevents regression.
- **Plan-killer R2-H3** (phase scope) — fixed by Phase 1a/1b/3 split
  with explicit dependencies.

### Judgment Calls (Round 2)

1. **R2-H3 split — 1.3.5 in 1a, not 1b.** The parallel-invocation gate
   (WI 1.3.5) is tightly coupled to WI 1.8 (tracking-setup marker);
   separating them across phases would be more confusing than
   useful. 1.3.5 stays in Phase 1a.
2. **R2-H3 split — WI 1.16 in 1b, not 1a.** WI 1.16 (append `pr:` to
   marker) is a marker-polish step; the happy path prints PR URL from
   WI 1.15's stdout, so 1.16 is additive. Test case 4 (happy path)
   checks PR URL on stdout, so it passes without 1.16. Spec-adherent
   to round-2 guidance.
3. **R2-M5 staleness window — 1 hour default.** Round 2 proposed "1h
   or 24h." Chose 1h because (a) /quickfix is fast — a marker older
   than 1h almost certainly means a dead pipeline; (b) 24h is too
   permissive — two parallel /quickfix runs in the same checkout, each
   finishing in <10 minutes, would need to serialize, and a stale 23h
   marker should still block a fresh run to flush stale state. Users
   can increase `STALE_AGE_SECONDS` if their fleet dictates otherwise.
4. **R2-M6 — mode-aware Co-Authored-By.** Chose "include only in
   agent-dispatched mode" over "always include." Rationale: the
   semantic payload is stronger — `git log --grep 'Co-Authored-By: Claude'`
   in a user-edited commit would be misleading, because the user
   authored the edits and /quickfix just shipped them. The
   `🤖 Generated with /quickfix (mode)` trailer is the stable tracking
   signal either way. Alternative (always-include) was rejected as
   semantically incorrect for user-edited.
5. **R2-L2 scope.** Self-assertion is best-effort: falls back to
   known install paths if `$0` is unusual (test harness may inject
   the skill). Non-fatal if the SKILL.md file cannot be located at
   all — the test harness sometimes invokes the body directly.
   Test case 31 writes an explicit SKILL.md with the key stripped.
6. **R2-H2 exit code 6.** Chose a new code (6) over reusing code 5
   because round-1's code 5 spans all operation failures; we need a
   distinct signal when the operation AND its cleanup both fail so
   the user knows the repo is in an intermediate state. Codes 0-5
   signal success / cancelled / recoverable state. Code 6 signals
   "manual intervention needed."

### Convergence Assessment (Round 2)

**Converged.** All 11 round-2 findings have explicit dispositions
with verified evidence. Plan-killer R2-H1 is fixed with a
live-reproducible acceptance criterion (any future refiner can grep
to verify). Plan-killer R2-H2's exit-code-6 cleanup convention is
tested by case 28. Phase 1a/1b split keeps each shippable phase to
~15 WIs and ~10-15 tests — within agent-session limits.

**Known open judgment items** (NOT blocking convergence, but flagged
so the Phase 1a implementation agent can escalate if needed):

1. **R2-M2 untracked-file limitation.** Agent-created new files are
   not auto-detected; the agent must state them in "done". If users
   find this unreliable in practice, Phase 4 could add a manual
   "new files?" confirmation prompt. Not in scope for v1.
2. **R2-M5 staleness window tuning.** If 1h is wrong in practice,
   bump to 6h / 24h. Easy change; config-exposed if needed.
3. **R2-L2 self-assertion path resolution.** If `$0` path discovery
   fails consistently in Claude Code invocations, add
   `ZSKILLS_SKILL_DIR` env var as a stronger hint. Monitor Phase 1b
   test case 31 stability.

**Round 3 should NOT be needed** if Phase 1a implementation follows
the plan text. The HIGHs are all live-verifiable (grep tests are
structural and run as part of the suite). If a Round 3 reviewer
surfaces new issues, they are most likely to be in the mode-aware
commit-message formatting (R2-M6 new code path) or the ls-remote
exit-code handling (R2-M4 new code path) — both worth a targeted
re-check.

## Round 3 Disposition

Round 3 was a focused convergence check (combined reviewer + DA, no full
adversarial pair) after the track-record pattern of refiners over-claiming
convergence. All three round-2 HIGH fixes were verified actually-in-plan-text
via direct grep against the file, not narrative trust. Result: **0 HIGHs
remaining, 1 MEDIUM (portability), 7 LOWs (stale refs, polish).**

| ID | Severity | Evidence | Disposition | Notes |
|----|----------|----------|-------------|-------|
| R3-F1 | LOW | Verified | Fixed inline | Line 829 "WI 2.5" → "WI 3.5" (stale ref from renumbering) |
| R3-F2 | LOW | Verified | Justified | Stale R1 disposition row for R-H8 — preserved as historical |
| R3-F3 | LOW | Verified | Justified | Round-2-appended assessment inside R1 section is annotation, not row mutation |
| R3-F4 | LOW | Verified | Fixed inline | Round History table row added for rounds 2 and 3 |
| R3-F5 | MEDIUM | Verified | Acknowledged | `date -d` is GNU-only; acceptable for Linux-primary zskills; implementer should note this when migrating |
| R3-F6 | LOW | Judgment | Justified | Stale-marker orphan hygiene — tracking hygiene only, no harm |
| R3-F7 | LOW | Judgment | Justified | Self-assertion fallback — documented as judgment call |
| R3-F8 | LOW | Judgment | Justified | Acceptance grep anchor sharpness — structural test still catches regression |
| R3-F9 | LOW | Partial | Justified | Stale-branch bash should be reviewed during implementation |

Round 3 verdict: **Convergent with cleanup.** The plan is ready for /run-plan.

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review.
**Convergence:** Converged at round 3 (0 HIGH findings remaining).
**Remaining concerns:** `date -d` GNU-only assumption for stale-marker detection (R3-F5 MEDIUM, acknowledged — Linux-primary OK). Low-severity polish items documented in Round 3 Disposition, non-blocking.

### Round-by-round structural changes

- **Round 1 → 2:** Round 1 caught the agent-dispatch layer ambiguity, the recovery-path contradiction, the git-status naive-parsing bug, and the plan-killer R-H1 (project hook blocks /quickfix's own commits when `unit_cmd != full_cmd`). Round 1 refiner resolved all 24 findings and claimed convergence — WRONG.
- **Round 2 → 3:** Round 2 review caught 3 NEW HIGHs the round-1 refinement introduced:
  - **R2-H1** — WI 1.19's `rm -rf "$MAIN_ROOT/..."` blocked by hook (live-reproduced; refiner's "empirical precedent" claim was wrong).
  - **R2-H2** — Cleanup paths added `|| true` suppression (violates CLAUDE.md; banned pattern per MEMORY).
  - **R2-H3** — Phase 1 scope exploded from 12 WIs to 20 (67% growth).
  Round 2 refiner split Phase 1 into 1a/1b, purged `|| true`, fixed the mirror idiom. Claimed convergence.
- **Round 3:** Final sanity check verified the three HIGH fixes actually landed in plan text (not just disposition narrative). Grep confirmed. Only low-severity polish remained; applied the trivial fixes inline.

### Lessons

Both `/create-worktree` (previous skill) and `/quickfix` had refiners claim convergence in at least one round that was wrong. The pattern is clear: **"refiner claims convergence" ≠ "plan is converged"** — subsequent adversarial review reliably finds new issues introduced by fixes. A minimum of 2 adversarial rounds is necessary for high-stakes plans; 3 is safer.

### Evidence discipline paid off

Round 1: the plan-killer R-H1 was caught by reading `hooks/block-unsafe-project.sh.template:188-229` — a specific file:line verification, not abstract review. Round 2: the R2-H1 hook block was caught by a LIVE REPRODUCER — the reviewer ran the exact command and the hook blocked it verbatim. Both rounds demonstrate the verify-before-fix gate works when reviewers cite concrete reproducers and refiners re-run them.

### Known judgment calls

- R-H1 option (c) adopted: hard-error if `unit_cmd != full_cmd`. Simpler than bypass mechanisms.
- R-H2 option (b) adopted: auto-cleanup on commit failure (checkout main, delete branch).
- `jq` as hard dependency (matches `/do`).
- Co-Authored-By mode-aware (present only in agent-dispatched mode).
- Phase 1 split into 1a (core, happy paths) and 1b (guards, edge cases).
- `date -d` GNU-only noted as R3-F5 MEDIUM — acceptable for zskills' Linux-primary deployment.
- Exit code 6 introduced for cleanup failures requiring manual intervention.
