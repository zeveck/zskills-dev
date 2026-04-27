---
title: Consumer stub-callout extension
created: 2026-04-25
status: active
---

# Plan: Consumer stub-callout extension

> **Landing mode: PR** -- This plan targets PR-based landing. All
> phases use worktree isolation with a named feature branch.

## Overview

Follow-up to `plans/SCRIPTS_INTO_SKILLS_PLAN.md`. That plan moved
Tier-1 machinery into owning skills and explicitly deferred the
"consumer stub-callout pattern" — a documented convention by which
zskills scripts defer to consumer-owned `scripts/<stub>.sh` files
when present. This plan delivers that convention, formalizes the
exit-code / stdout contract, wires three new callouts
(`post-create-worktree.sh`, `dev-port.sh`, `start-dev.sh`), and
converts the two remaining "illusory implementations" (`stop-dev.sh`,
`test-all.sh`) into honest failing stubs with documented contracts.

**Phase 1 is a hard staleness gate.** If `SCRIPTS_INTO_SKILLS_PLAN.md`
has not landed (frontmatter `status: complete`, post-refactor
filesystem state, CHANGELOG entry), Phase 1 emits an actionable error
and `exit 1`s — `/run-plan` halts cleanly via the Failure Protocol
without modifying the plan's `status: active` frontmatter, so a
re-run after the prerequisite lands will re-hit the gate and pass.
The implementing agent **MUST NOT** attempt to land the prerequisite
itself; the user owns ordering.

**Two motivations:**

1. **Make the contract explicit.** Today `stop-dev.sh` requires the
   undocumented `var/dev.pid` PID-file contract (silently no-op if
   absent); `test-all.sh` ships with `{{E2E_TEST_CMD}}` literals that
   error at runtime with bash "command not found" (exit 127). Both
   pretend to be working implementations. Failing stubs with
   documented contracts force the consumer to acknowledge what
   zskills expects.
2. **Open the right extension points.** `create-worktree.sh` and
   `port.sh` both have natural consumer-customization seams that
   don't exist today. Formalize one convention so future seams (e.g.
   `briefing-extra.sh`, `post-land.sh`) follow a known pattern
   instead of reinventing per-callout.

## Stub inventory

| Stub                       | Caller                        | New / convert          | Behavior on absent        |
|----------------------------|-------------------------------|------------------------|---------------------------|
| `post-create-worktree.sh`  | `create-worktree.sh` (end)    | NEW                    | no-op (worktree completes)|
| `dev-port.sh`              | `port.sh` (post env-override) | NEW                    | built-in algorithm        |
| `start-dev.sh`             | (consumer-invoked)            | NEW (failing stub)     | n/a (stub IS the file)    |
| `stop-dev.sh`              | (consumer-invoked, hook help) | CONVERT to failing stub| n/a (stub IS the file)    |
| `test-all.sh`              | run-plan / verify-changes     | CONVERT to failing stub| `command not found` → `exit 1` with message |
| `briefing-extra.sh`        | `briefing.cjs`                | DEFERRED (Phase 6)     | n/a                        |

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Staleness gate (halt if SCRIPTS_INTO_SKILLS_PLAN not landed) | ⬚ |  |  |
| 2 — Stub-callout convention + sourceable dispatch helper | ⬚ |  |  |
| 3 — `post-create-worktree.sh` callout in `create-worktree.sh` | ⬚ |  |  |
| 4 — `dev-port.sh` callout in `port.sh` | ⬚ |  |  |
| 5 — `start-dev.sh` (new) + convert `stop-dev.sh` / `test-all.sh` to failing stubs | ⬚ |  |  |
| 6 — Hooks / CLAUDE_TEMPLATE / docs sweep + `briefing-extra.sh` decision | ⬚ |  |  |
| 7 — CHANGELOG, plan index, frontmatter flip | ⬚ |  |  |

## Phase 1 — Staleness gate

### Goal

Halt `/run-plan` cleanly if `plans/SCRIPTS_INTO_SKILLS_PLAN.md` has
not landed. Surface an actionable error so the user can run the
prerequisite, then re-run this plan.

### Work Items

- [ ] 1.1 — **Frontmatter check.**
      ```bash
      grep -F 'status: complete' plans/SCRIPTS_INTO_SKILLS_PLAN.md \
        || { echo "FAIL: prerequisite plan frontmatter not 'status: complete'"; FAIL=1; }
      ```
- [ ] 1.2 — **Multi-anchor filesystem check.** Verify the post-refactor
      state via three symmetric absent/present pairs **plus** the
      load-bearing test-runner export. Asymmetric coverage would
      false-pass on partial-completion / partial-rollback states.
      Each anchor gets its own named FAIL message so an implementer
      can see at a glance which anchor broke (instead of bisecting
      a 7-condition compound):
      ```bash
      test ! -e scripts/port.sh \
        || { echo "FAIL: legacy scripts/port.sh still present" >&2; FAIL=1; }
      test -f skills/update-zskills/scripts/port.sh \
        || { echo "FAIL: skills/update-zskills/scripts/port.sh missing" >&2; FAIL=1; }
      test ! -e scripts/sanitize-pipeline-id.sh \
        || { echo "FAIL: legacy scripts/sanitize-pipeline-id.sh still present" >&2; FAIL=1; }
      test -f skills/create-worktree/scripts/sanitize-pipeline-id.sh \
        || { echo "FAIL: skills/create-worktree/scripts/sanitize-pipeline-id.sh missing" >&2; FAIL=1; }
      test ! -e scripts/clear-tracking.sh \
        || { echo "FAIL: legacy scripts/clear-tracking.sh still present" >&2; FAIL=1; }
      test -f skills/update-zskills/scripts/clear-tracking.sh \
        || { echo "FAIL: skills/update-zskills/scripts/clear-tracking.sh missing" >&2; FAIL=1; }
      test -f skills/commit/scripts/write-landed.sh \
        || { echo "FAIL: skills/commit/scripts/write-landed.sh missing" >&2; FAIL=1; }
      grep -qF 'export CLAUDE_PROJECT_DIR' tests/run-all.sh \
        || { echo "FAIL: tests/run-all.sh missing CLAUDE_PROJECT_DIR export (prereq Phase 5 WI 5.7)" >&2; FAIL=1; }
      ```
      The `grep -qF 'export CLAUDE_PROJECT_DIR' tests/run-all.sh`
      check is load-bearing: prerequisite plan WI 5.7 adds this
      export so cross-skill `${CLAUDE_PROJECT_DIR:-...}` lib
      resolution works inside `tests/run-all.sh`. Without it,
      Phase 3.4 / 4.5 stub tests silently no-op (lib path resolves
      under empty `$CLAUDE_PROJECT_DIR`).
- [ ] 1.3 — **CHANGELOG entry check.** The prerequisite plan does
      not pin a verbatim commit-message string in its Phase 6, so
      we use a tolerant regex that captures the spirit (Tier-1 →
      owning skills) without breaking on minor copy-edits:
      ```bash
      grep -E 'Tier.?1.*owning skills?|move.*scripts.*into.*skills|relocate.*scripts.*under.*skills' CHANGELOG.md \
        || { echo "FAIL: CHANGELOG entry for Tier-1 scripts → owning skills not found"; FAIL=1; }
      ```
- [ ] 1.4 — **Halt with actionable message on any failure.** If `FAIL`
      is set after 1.1–1.3, emit to stderr and `exit 1`:
      ```bash
      if [ -n "$FAIL" ]; then
        cat >&2 <<'EOF'
      HALT: This plan depends on plans/SCRIPTS_INTO_SKILLS_PLAN.md landing first.

      Prerequisite check failed (see PASS/FAIL lines above).

      Fix:
        1. /run-plan plans/SCRIPTS_INTO_SKILLS_PLAN.md
        2. Wait for it to land (status: complete in frontmatter,
           CHANGELOG entry written).
        3. /run-plan plans/CONSUMER_STUB_CALLOUTS_PLAN.md
        (Optional, if more than ~1 week elapsed between the prereq
        landing and this re-run: /refine-plan first to catch line-
        number drift in this plan's :NNN citations.)
      EOF
        exit 1
      fi
      ```

### Design & Constraints

**Halt mechanism (verified).** `/run-plan` halts on non-zero WI exit
without retry. See `skills/run-plan/SKILL.md:1712-1716` (phase-fail
behavior) and `skills/run-plan/references/failure-protocol.md` (the
"Run Failed" stderr template + frontmatter preservation). Phase 1 in
`/run-plan` is preflight-style: a non-zero exit halts the orchestrator
immediately.

**Frontmatter preservation.** Frontmatter `status: complete` is only
written by `/run-plan` after final verification (see
`skills/run-plan/SKILL.md:1514-1521`). When Phase 1 halts here, the
plan's `status: active` is unchanged, so re-running re-hits Phase 1.
The user fixes the prerequisite, re-runs, gate passes, plan proceeds.

**Multi-anchor over single-file.** A single `test -f` could
false-pass if one prerequisite-plan WI partially landed. Symmetric
absent/present pairs (port.sh, sanitize-pipeline-id.sh,
clear-tracking.sh) catch partial-completion and partial-rollback.
The `tests/run-all.sh export CLAUDE_PROJECT_DIR` anchor is
load-bearing for cross-skill lib resolution in this plan's stub
tests; without it Phase 3.4 / 4.5 silently no-op.

**No remediation by the implementing agent.** Per the user
instruction and the broader "surface bugs, don't patch" principle
(`feedback_no_premature_backcompat.md` adjacent: don't quietly route
around an unmet precondition): the agent emits the failure and
exits. It does **not** attempt to invoke `/run-plan` on the
prerequisite itself.

**No jq.** Per `feedback_no_jq_in_skills.md`: pure `grep -F` and
shell tests; nothing parses JSON here.

**No mirror discipline applies** — Phase 1 only reads files.

### Acceptance Criteria

- [ ] WI 1.1 grep matches `status: complete` in
      `plans/SCRIPTS_INTO_SKILLS_PLAN.md`.
- [ ] WI 1.2 multi-anchor compound test passes (rc 0).
- [ ] WI 1.3 grep matches `refactor(scripts): move Tier-1 scripts
      into owning skills` in `CHANGELOG.md`.
- [ ] **No live-tree halt-path test.** Per CLAUDE.md "Never modify
      the working tree to check if a failure is pre-existing" —
      do NOT rename `CHANGELOG.md` or any source file to test the
      halt path. The shell-mechanics of `exit 1` halting `/run-plan`
      are already verified in the Design ("Halt mechanism (verified)"
      below); we trust that and the per-WI checks above. If
      curious, an implementer may verify halt-path behavior in a
      throwaway `mktemp -d` copy.

### Dependencies

None — this is the gate.

## Phase 2 — Stub-callout convention + sourceable dispatch helper

### Goal

Document the formal contract once; ship a tested, sourceable bash
helper used by every callout site.

### Work Items

- [ ] 2.1 — **Write the convention** at
      `skills/update-zskills/references/stub-callouts.md` (new
      file). Include the contract, the helper-function source
      verbatim, the canonical-stubs table (the inventory above), and
      a short prose section explaining when to add a new callout.
      The contract:
      > **zskills consumer stub-callout contract**
      > 1. zskills checks for the consumer stub at
      >    `$REPO_ROOT/scripts/<stub-name>.sh`.
      > 2. The stub must be executable (`-x` test). If the file
      >    exists but is not executable, zskills emits a one-line
      >    warning to stderr (`zskills: scripts/<stub>.sh present
      >    but not executable; ignoring (chmod +x to enable)`) and
      >    treats it as absent.
      > 3. zskills invokes the stub with documented positional
      >    arguments (per-stub; see canonical table).
      > 4. **stdout:** zskills captures stdout and uses it where
      >    documented (per-stub; e.g. `dev-port.sh` expects a
      >    numeric port).
      > 5. **exit code:**
      >    - `0` + non-empty stdout → honor stdout where applicable;
      >      where not (e.g. `post-create-worktree.sh`), treat as
      >      success.
      >    - `0` + empty stdout → no-op; zskills falls through to
      >      its built-in default.
      >    - non-zero → propagate failure; zskills surfaces the
      >      stub's stderr and exits non-zero with a propagation rc
      >      (see per-callout phases for specific rc).
      > 6. **First-run note:** zskills emits a one-line stderr note
      >    the first time a stub is encountered in a project (gated
      >    by absence of `.zskills/stub-notes/<stub>.noted`; the
      >    file is touched after the first note).
- [ ] 2.2 — **Create the sourceable helper** at
      `skills/update-zskills/scripts/zskills-stub-lib.sh`. The lib
      defines one function:
      ```bash
      #!/bin/bash
      # zskills-stub-lib.sh -- sourceable dispatcher for consumer
      # stub-callouts. See
      # .claude/skills/update-zskills/references/stub-callouts.md.
      #
      # Usage:
      #   source "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
      #   zskills_dispatch_stub <stub-name> <repo-root> -- arg1 arg2 ...
      #
      # Sets:
      #   ZSKILLS_STUB_RC          - exit code from stub (or 0 if absent)
      #   ZSKILLS_STUB_STDOUT      - captured stdout (or "" if absent)
      #   ZSKILLS_STUB_INVOKED     - "1" iff the stub ran
      zskills_dispatch_stub() {
        local name=$1
        local repo_root=$2
        shift 2
        [ "$1" = "--" ] && shift
        local stub="$repo_root/scripts/$name"
        ZSKILLS_STUB_RC=0
        ZSKILLS_STUB_STDOUT=""
        ZSKILLS_STUB_INVOKED=0
        if [ ! -e "$stub" ]; then
          return 0
        fi
        if [ ! -x "$stub" ]; then
          echo "zskills: scripts/$name present but not executable; ignoring (chmod +x to enable)" >&2
          return 0
        fi
        local notes_dir="$repo_root/.zskills/stub-notes"
        local marker="$notes_dir/$name.noted"
        if [ ! -f "$marker" ]; then
          mkdir -p "$notes_dir"
          touch "$marker" 2>/dev/null || true
          echo "zskills: invoking consumer stub scripts/$name (one-time note; see .claude/skills/update-zskills/references/stub-callouts.md)" >&2
        fi
        ZSKILLS_STUB_INVOKED=1
        ZSKILLS_STUB_STDOUT=$(bash "$stub" "$@")
        ZSKILLS_STUB_RC=$?
        if [ "$ZSKILLS_STUB_RC" -ne 0 ]; then
          echo "zskills: scripts/$name exited $ZSKILLS_STUB_RC" >&2
        fi
        return 0
      }
      ```
- [ ] 2.3 — **Tests** at `tests/test-stub-callouts.sh`. Mirror the
      `tests/test-create-worktree.sh:828-836` fake-consumer-project
      pattern. Cases:
      1. `stub-absent` → `INVOKED=0`, `RC=0`, `STDOUT=""`.
      2. `stub-present-with-stdout` → `INVOKED=1`, `RC=0`, `STDOUT`
         matches expected.
      3. `stub-present-empty-stdout` → `INVOKED=1`, `RC=0`,
         `STDOUT=""`.
      4. `stub-non-executable` → `INVOKED=0`, expected stderr warning
         emitted (capture stderr to a temp file, grep).
      5. `stub-exits-nonzero` → `INVOKED=1`, `RC` matches stub's exit
         code; stderr matches `scripts/<name> exited <rc>`.
      6. **First-run note:** first call emits the `one-time note`
         stderr line; second call in same project does not (marker
         present at `.zskills/stub-notes/<stub>.noted`).
      7. **Multi-invocation clean state:** call dispatcher with
         `stub-A` (returns "hello"), then with `stub-B` (absent);
         second call's `STDOUT=""` and `INVOKED=0` (no stale state
         from first call).
      Add `tests/test-stub-callouts.sh` to `tests/run-all.sh`.
- [ ] 2.4 — **Extend `/update-zskills` Step D to copy from
      `stubs/`.** Stubs ship at
      `skills/update-zskills/stubs/<name>.sh` (a new directory,
      parallel to `scripts/` — not `scripts/`, since they're
      consumer-installed templates rather than skill-callable
      tools). Step D currently only copies "from
      `$PORTABLE/scripts/`" (verified at SKILL.md:897). Edit Step
      D's copy-loop / source-dir list to **also** copy missing
      files from `$PORTABLE/skills/update-zskills/stubs/` to the
      consumer's `scripts/` (skip-if-exists). Document this dual
      source explicitly in the Step D prose:
      > Copy missing scripts from `$PORTABLE/scripts/` and from
      > `$PORTABLE/skills/update-zskills/stubs/` to `scripts/`
      > (verify executable bit is preserved). The `stubs/` dir
      > holds consumer-customizable failing-stub / no-op
      > templates; `scripts/` holds zskills-managed tools.
      AC: `grep -F 'skills/update-zskills/stubs/' skills/update-zskills/SKILL.md` ≥ 1.
- [ ] 2.5 — **Mirror** `update-zskills`:
      ```bash
      rm -rf .claude/skills/update-zskills && \
        cp -a skills/update-zskills/ .claude/skills/update-zskills/
      ```

### Design & Constraints

**Why sourceable, not inline.** Three callers (Phases 3, 4 and
implicitly Phase 5's failing-stub messaging) plus the test suite
need this dispatch logic. Inlining duplicates ~25 lines × 3 (lib body
plus invocation idiom). The
`skills/create-worktree/scripts/sanitize-pipeline-id.sh`
cross-skill-invocation pattern from the prerequisite plan
demonstrates that a script in one skill can be reliably resolved by
callers in another via `$CLAUDE_PROJECT_DIR/.claude/skills/<owner>/scripts/<name>`.
This lib lives in `update-zskills` (the infrastructure skill) and is
**sourced** (not exec'd) by callers — they need the function in
their own shell to access `$ZSKILLS_STUB_*` variables after the call.
This is the first sourceable lib in zskills; precedent matters, so
its tests must pin behavior tightly.

**Cross-skill resolution form.** Callers source via
`. "$CLAUDE_PROJECT_DIR/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"`
(bare `$CLAUDE_PROJECT_DIR` form per the prerequisite plan's Phase 1
Design). Tests source via the absolute repo-root form
`. "$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh"`
(consistent with prerequisite plan WI 5.7's
`tests/run-all.sh` `CLAUDE_PROJECT_DIR` export — works either way).

**No jq.** The lib does no JSON parsing. Per
`feedback_no_jq_in_skills.md`.

**No timeout in the lib itself.** Stubs vary too widely to share a
default (`dev-port.sh` should be sub-second; `post-create-worktree.sh`
running `npm install` legitimately takes minutes). The lib runs
stubs synchronously without `timeout(1)` wrapping. Individual
callsites that care about latency (e.g. `dev-port.sh` is called on
every port query) MAY wrap the dispatcher call in `timeout 10s`,
documented per-callout.

**Stub stdout/stderr handling.** The lib captures stdout into
`ZSKILLS_STUB_STDOUT` (single-shot, full output). Stderr is NOT
captured — it streams through to the caller's stderr so progress
output (e.g. `npm install`) stays visible. Callouts that want
progress on stdout (rare) should run via a passthrough form — not
implemented in this plan; reachable by adding a `--stdout=stream`
flag to the dispatcher in a future PR.

**Mirror discipline.** WI 2.4 is the only skill edit in this phase;
batched cp per `feedback_claude_skills_permissions.md`.

**First-run marker scope.** Markers live at
`.zskills/stub-notes/<stub>.noted` (per project; `.zskills/` is the
existing zskills-managed directory and is the right home for
agent-written ephemeral state per
`feedback_claude_dir_prompts.md` — `.claude/` writes trigger
permission prompts, `.zskills/` does not). The note is one line,
cheap; the marker prevents per-invocation noise. We deliberately do
NOT write under `var/` — zskills' own `.gitignore` does not list
`var/`, and consumer projects vary; using `.zskills/` avoids
creating a surprise directory in foreign projects.

**Stub non-zero rc contract (pinned).** If the stub exits non-zero,
the lib (a) sets `ZSKILLS_STUB_RC` to the stub's exit code unchanged,
(b) emits a single stderr line `zskills: scripts/<name> exited <rc>`,
(c) returns 0 itself (the lib never propagates the stub's failure
itself — the caller decides). The stub's stdout (captured into
`ZSKILLS_STUB_STDOUT`) is preserved as-is; the stub's stderr is NOT
captured (it passes through to the caller's stderr). The caller
inspects `ZSKILLS_STUB_RC` and `ZSKILLS_STUB_INVOKED` and decides
whether to abort, fall through, or warn-and-continue. This contract
is documented verbatim in `references/stub-callouts.md`.

### Acceptance Criteria

- [ ] `test -f skills/update-zskills/references/stub-callouts.md` and
      mirrored copy.
- [ ] `test -x skills/update-zskills/scripts/zskills-stub-lib.sh` and
      mirrored copy.
- [ ] `bash tests/test-stub-callouts.sh` exits 0; PASS lines for all
      7 cases above (including multi-invocation clean-state).
- [ ] `grep -c 'test-stub-callouts.sh' tests/run-all.sh` ≥ 1.
- [ ] **Test sources lib via source-tree path, not via mirror:**
      `! grep -F '$CLAUDE_PROJECT_DIR' tests/test-stub-callouts.sh`
      (zero matches — test must source the lib via
      `$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh`
      so it works in fresh `tests/run-all.sh` runs without depending
      on `.claude/skills/` mirror state).
- [ ] `grep -F 'skills/update-zskills/stubs/' skills/update-zskills/SKILL.md`
      ≥ 1 (Step D extended to copy from `stubs/`).
- [ ] **Lib-missing stderr warning wired at both callsites:**
      `grep -F 'stub-lib missing' skills/create-worktree/scripts/create-worktree.sh skills/update-zskills/scripts/port.sh`
      returns ≥ 2 matches (one per callsite; warns when
      `$CLAUDE_PROJECT_DIR` is set but the cross-skill lib path
      doesn't resolve — surfaces a broken install instead of silently
      no-op'ing all consumer stubs).
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills`
      empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1.

## Phase 3 — `post-create-worktree.sh` callout

### Goal

Consumer can run setup steps (cp `.env.local`, `npm install`,
seed-data restore) at the end of `create-worktree.sh`. The callout
fires after the worktree is fully created and tracking files are
written, before `create-worktree.sh` prints the worktree path on
stdout.

### Work Items

- [ ] 3.1 — **Wire the callout** in
      `skills/create-worktree/scripts/create-worktree.sh`
      (post-prerequisite-plan path; verify with
      `tail -10 skills/create-worktree/scripts/create-worktree.sh` —
      the final block today is verbatim from
      `scripts/create-worktree.sh:337-341`):
      ```bash
      # ──────────────────────────────────────────────────────────────────
      # WI 1a.11 — Rollback on .zskills-tracked write failure.
      if ! printf '%s\n' "$PIPELINE_ID" > "$WT_PATH/.zskills-tracked"; then
        ...
      fi

      if [ -n "$PURPOSE" ]; then
        ...
      fi

      # ──────────────────────────────────────────────────────────────────
      # WI 1a.12 — Final stdout: exactly one line with the path.
      # ──────────────────────────────────────────────────────────────────
      printf '%s\n' "$WT_PATH"
      exit 0
      ```
      Insert **after the `.worktreepurpose` block, before the
      `printf '%s\n' "$WT_PATH"` line**:
      ```bash
      # ──────────────────────────────────────────────────────────────────
      # WI 3.1 — Consumer post-create-worktree callout.
      # See .claude/skills/update-zskills/references/stub-callouts.md.
      # ──────────────────────────────────────────────────────────────────
      _STUB_LIB="${CLAUDE_PROJECT_DIR:-$MAIN_ROOT}/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
      if [ -f "$_STUB_LIB" ]; then
        # shellcheck disable=SC1090
        . "$_STUB_LIB"
        zskills_dispatch_stub post-create-worktree.sh "$MAIN_ROOT" -- \
          "$WT_PATH" "$BRANCH" "$SLUG" "$PREFIX" "$PIPELINE_ID" "$MAIN_ROOT"
        if [ "${ZSKILLS_STUB_INVOKED:-0}" = "1" ] && [ "${ZSKILLS_STUB_RC:-0}" -ne 0 ]; then
          echo "create-worktree: post-create-worktree.sh exited ${ZSKILLS_STUB_RC}; worktree $WT_PATH left in place for inspection" >&2
          exit 9
        fi
      elif [ -n "$CLAUDE_PROJECT_DIR" ]; then
        echo "create-worktree: stub-lib missing at $_STUB_LIB; consumer stubs disabled. Run /update-zskills to repair." >&2
      fi
      unset _STUB_LIB
      ```
      The lib-fallback `[ -f "$_STUB_LIB" ]` makes this code safe in
      tests that don't install the lib (which would be a bug, but
      defensive against partial installs). The `elif [ -n
      "$CLAUDE_PROJECT_DIR" ]` branch warns to stderr ONLY when in
      installed runtime (cross-skill harness sets
      `$CLAUDE_PROJECT_DIR`); silent in test mode where the lib is
      sourced via `$REPO_ROOT` path before this guard. Surfaces a
      broken `/update-zskills` install loudly per "surface bugs,
      don't patch" rather than silently no-op every callout.
- [ ] 3.2 — **Add stub to `/update-zskills` Step D copy list.**
      Edit `skills/update-zskills/SKILL.md` Step D (lines 895–910;
      verify via `grep -nE '#### Step D|Copy.*if missing' skills/update-zskills/SKILL.md`).
      After the existing `clear-tracking.sh` / `apply-preset.sh` /
      `stop-dev.sh` bullets, add:
      > - Copy `post-create-worktree.sh` if missing — invoked by the
      >   `/create-worktree` skill's worktree-creation script after a
      >   successful create. Stub is a documented no-op; consumer
      >   replaces with setup steps (cp `.env.local`, `npm install`,
      >   etc.). See `.claude/skills/update-zskills/references/stub-callouts.md`.
- [ ] 3.3 — **Create the stub source** at
      `skills/update-zskills/stubs/post-create-worktree.sh`. New
      directory `skills/update-zskills/stubs/` (parallel to
      `scripts/`, holds files copied to consumer `scripts/`).
      Content:
      ```bash
      #!/bin/bash
      # post-create-worktree.sh -- runs after a /create-worktree
      # invocation succeeds. Replace this no-op with your own setup
      # logic (cp .env.local, npm install, seed restore, etc.).
      #
      # Arguments (positional):
      #   $1  WT_PATH       absolute worktree path
      #   $2  BRANCH        feature branch name
      #   $3  SLUG          slug portion of branch
      #   $4  PREFIX        prefix portion of branch (or empty)
      #   $5  PIPELINE_ID   pipeline ID written to .zskills-tracked
      #   $6  MAIN_ROOT     source repo root (for cp .env.local etc.)
      #
      # Exit code: non-zero fails create-worktree (the worktree is
      # left in place for inspection — clean it up manually if you
      # want it gone). Empty stdout = no-op; zskills ignores stdout
      # for this callout.
      #
      # See .claude/skills/update-zskills/references/stub-callouts.md.
      exit 0
      ```
      (Step D's copy-loop is already extended in Phase 2 WI 2.4 to
      pick up `stubs/`. This WI just lands the stub source file
      itself.)
- [ ] 3.4 — **Tests** at `tests/test-post-create-worktree.sh` (new).
      Three cases against a fake consumer project (mirror the
      `tests/test-create-worktree.sh:828-836` fixture pattern, plus
      install the stub-lib path):
      1. `stub-absent` — create-worktree succeeds; no stub invoked
         (no `.zskills/stub-notes/post-create-worktree.sh.noted`
         marker).
      2. `stub-present-success` — install a stub that touches
         `$WT_PATH/POST_RAN`; verify create-worktree exits 0,
         `$WT_PATH/POST_RAN` exists.
      3. `stub-present-fail` — install a stub that `exit 7`s; verify
         create-worktree exits **9** (the propagation code),
         worktree directory **still exists** (left for inspection),
         stderr matches `post-create-worktree.sh exited 7`.
      Add to `tests/run-all.sh`.
- [ ] 3.5 — **Mirror** `create-worktree` and (already done in 2.4
      but re-run if any incremental edit) `update-zskills`:
      ```bash
      rm -rf .claude/skills/create-worktree && \
        cp -a skills/create-worktree/ .claude/skills/create-worktree/
      rm -rf .claude/skills/update-zskills && \
        cp -a skills/update-zskills/ .claude/skills/update-zskills/
      ```

### Design & Constraints

**Insertion point verification.** The verbatim 5-line block in WI
3.1 is from the **post-prerequisite-plan** path
(`skills/create-worktree/scripts/create-worktree.sh`). The drafter
verified this against the current `scripts/create-worktree.sh`
(lines 320–341); the SCRIPTS_INTO_SKILLS_PLAN's Phase 3a moves the
file via `git mv` without rewriting the tail, so the verbatim block
is preserved. If the prerequisite plan rewrote the tail
unexpectedly, `/refine-plan` flags it; otherwise the insertion
point matches.

**Rollback semantics decision.** On stub failure: **leave the
worktree in place; exit 9.** Rationale: the worktree is fully
created and tracked; rolling back means destroying state the user
might want to inspect (the stub may have done partial work). Failure
mode is an explicit non-zero rc with a stderr message naming the
worktree path; user can `git worktree remove --force` if they want
it gone. The alternative — auto-rollback on stub failure — risks
destroying the consumer's partial setup work and was rejected.
Document this in `references/stub-callouts.md`.

**Exit code 9.** rc 8 is taken by the existing `.zskills-tracked`
write-failure path (line 326); rc 9 is the next free slot.
Spot-checked downstream: `/run-plan` failure protocol uses generic
non-zero handling, no special-case for rc 9; tests treat any
non-zero as failure.

**Failure-semantics contrast with neighboring blocks (DA4).** The
`.zskills-tracked` and `.worktreepurpose` write-failure paths
(lines 322–334) destroy the worktree via
`git worktree remove --force` then `exit 8`. The post-create stub
failure path (this WI) **preserves** the worktree and `exit 9`s.
The semantics are intentionally different: write failures are
zskills-internal contract violations (revert, ask user to retry);
stub failures are consumer-side and the stub may have done
arbitrary partial work that the user wants to inspect. Document
this distinction in `references/stub-callouts.md` so future
maintainers don't "harmonize" the two.

**Argument list.** Six positional args:
`WT_PATH BRANCH SLUG PREFIX PIPELINE_ID MAIN_ROOT`. All six are in
scope at the insertion point. `MAIN_ROOT` is included because
common consumer setup (cp `$MAIN_ROOT/.env.local`, copy template
files, run `git -C "$MAIN_ROOT"` queries) needs it and it's never
empty. `PURPOSE` was considered but is optional and may be empty;
keep it out of the positional list (the stub can read
`$WT_PATH/.worktreepurpose` if it cares).

**Stub-lib resolution.** Use `${CLAUDE_PROJECT_DIR:-$MAIN_ROOT}` —
both are absolute paths in scope at this point in
create-worktree.sh; `$MAIN_ROOT` is the same-skill anchor and
`$CLAUDE_PROJECT_DIR` is the cross-skill harness contract. This is
not the bare-`$CLAUDE_PROJECT_DIR` cross-skill form (per
prerequisite Phase 1 Design) because we're sourcing **out of**
create-worktree's own context, not invoking from skill prose; the
fallback to `$MAIN_ROOT` keeps source-tree tests working when
`$CLAUDE_PROJECT_DIR` is unset (it's exported by `tests/run-all.sh`
post-prerequisite, but defensiveness costs nothing).

**Mirror discipline.** WIs touch both `create-worktree/` and
`update-zskills/`; both mirror in WI 3.5.

**No jq.** No JSON involved.

### Acceptance Criteria

- [ ] `grep -c 'zskills_dispatch_stub post-create-worktree.sh'
      skills/create-worktree/scripts/create-worktree.sh` = 1.
- [ ] `test -x skills/update-zskills/stubs/post-create-worktree.sh`.
- [ ] `grep -F 'post-create-worktree.sh if missing'
      skills/update-zskills/SKILL.md` matches.
- [ ] `bash tests/test-post-create-worktree.sh` exits 0; PASS lines
      for all 3 cases.
- [ ] `diff -r skills/create-worktree .claude/skills/create-worktree`
      empty; same for `update-zskills`.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1, Phase 2 (lib must exist).

## Phase 4 — `dev-port.sh` callout

### Goal

Consumer can override the worktree port-derivation algorithm
(common case: a port-allocator service in the consumer's environment).

### Work Items

- [ ] 4.1 — **Wire the callout** in
      `skills/update-zskills/scripts/port.sh` (post-prerequisite-plan
      path; verify with `head -50 skills/update-zskills/scripts/port.sh`).
      Insertion point: **after the `DEV_PORT` env-var override (line
      37), before the main-repo check (line 39).** Verbatim before
      block (current `scripts/port.sh:33-43`):
      ```bash
      # DEV_PORT env var overrides everything
      if [[ -n "$DEV_PORT" ]]; then
        echo "$DEV_PORT"
        exit 0
      fi

      # Main repo gets the default port
      if [[ -n "$MAIN_REPO" ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
        echo "$DEFAULT_PORT"
        exit 0
      fi
      ```
      After block:
      ```bash
      # DEV_PORT env var overrides everything
      if [[ -n "$DEV_PORT" ]]; then
        echo "$DEV_PORT"
        exit 0
      fi

      # ─── Consumer dev-port.sh callout (stub-callout convention) ───
      _STUB_LIB="${CLAUDE_PROJECT_DIR:-$PROJECT_ROOT}/.claude/skills/update-zskills/scripts/zskills-stub-lib.sh"
      if [ -f "$_STUB_LIB" ]; then
        # shellcheck disable=SC1090
        . "$_STUB_LIB"
        zskills_dispatch_stub dev-port.sh "$PROJECT_ROOT" -- \
          "$PROJECT_ROOT" "$MAIN_REPO"
        if [ "${ZSKILLS_STUB_INVOKED:-0}" = "1" ] && [ "${ZSKILLS_STUB_RC:-0}" -eq 0 ]; then
          # Trim leading/trailing whitespace; require a positive
          # integer (no leading zero, no embedded newlines, rejects
          # bare "0" which is not a valid TCP port).
          _PORT_TRIMMED="${ZSKILLS_STUB_STDOUT#"${ZSKILLS_STUB_STDOUT%%[![:space:]]*}"}"
          _PORT_TRIMMED="${_PORT_TRIMMED%"${_PORT_TRIMMED##*[![:space:]]}"}"
          if [[ "$_PORT_TRIMMED" =~ ^[1-9][0-9]+$ ]]; then
            echo "$_PORT_TRIMMED"
            exit 0
          elif [ -n "$_PORT_TRIMMED" ]; then
            echo "zskills: dev-port.sh returned non-numeric/invalid stdout '$ZSKILLS_STUB_STDOUT'; falling through to built-in" >&2
          fi
          # empty stdout = silent fall-through (no warning)
          unset _PORT_TRIMMED
        fi
        # non-zero rc from stub: also fall through (warning emitted by lib)
      elif [ -n "$CLAUDE_PROJECT_DIR" ]; then
        echo "port.sh: stub-lib missing at $_STUB_LIB; consumer stubs disabled. Run /update-zskills to repair." >&2
      fi
      unset _STUB_LIB

      # Main repo gets the default port
      if [[ -n "$MAIN_REPO" ]] && [[ "$PROJECT_ROOT" == "$MAIN_REPO" ]]; then
        echo "$DEFAULT_PORT"
        exit 0
      fi
      ```
      **Note (verified):** `port.sh:27` does `unset _ZSK_REPO_ROOT
      _ZSK_CFG`, so `$_ZSK_REPO_ROOT` is **empty** at the insertion
      point (line 38). `$PROJECT_ROOT` is set at line 12 of `port.sh`
      (`PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`) and never
      unset — that's the canonical in-scope variable. Use
      `${CLAUDE_PROJECT_DIR:-$PROJECT_ROOT}` for the lib path and
      bare `"$PROJECT_ROOT"` as the dispatch arg. Verbatim. Do not
      re-introduce `_ZSK_REPO_ROOT`.
- [ ] 4.2 — **Stub source** at
      `skills/update-zskills/stubs/dev-port.sh`. Content:
      ```bash
      #!/bin/bash
      # dev-port.sh -- override port derivation for this project.
      # Print the desired port to stdout and exit 0; or exit 0 with
      # empty stdout to fall through to the built-in algorithm
      # (8080 for main repo; deterministic hash 9000-60000 per
      # worktree).
      #
      # Arguments (positional):
      #   $1  PROJECT_ROOT  current project root
      #   $2  MAIN_REPO     configured main_repo_path (or "")
      #
      # Example: derive port from a `.port` file at the project root.
      #
      #   if [ -f "$1/.port" ]; then
      #     cat "$1/.port"
      #   fi
      #
      # See .claude/skills/update-zskills/references/stub-callouts.md.
      exit 0
      ```
- [ ] 4.3 — **`/update-zskills` Step D bullet:**
      > - Copy `dev-port.sh` if missing — invoked by `port.sh`
      >   (lives in the `update-zskills` skill) after the
      >   `DEV_PORT` env override; if non-empty numeric stdout is
      >   returned, that value is used as the port. See
      >   `.claude/skills/update-zskills/references/stub-callouts.md`.
- [ ] 4.4 — **Update `references/stub-callouts.md`** with the
      `dev-port.sh` row in the canonical-stubs table.
- [ ] 4.5 — **Tests** in `tests/test-port.sh` (extend existing).
      Five cases:
      1. `stub-absent` → built-in default for main-repo case (8080)
         and worktree-hash case.
      2. `stub-returns-numeric` → stub `echo 12345; exit 0` →
         output `12345`.
      3. `stub-returns-empty` → stub `exit 0` (no stdout) →
         built-in.
      4. `stub-returns-non-numeric` → stub `echo notaport; exit 0`
         → built-in, stderr matches `non-numeric stdout`.
      5. `stub-non-executable` → stub installed without `chmod +x`
         → built-in, stderr matches `present but not executable`.
      Plus a sixth (sanity): `DEV_PORT` env var still wins when
      stub is also present (env-var check is *before* the stub).
- [ ] 4.6 — **Mirror** `update-zskills`.

### Design & Constraints

**Decision: warn + fall through on non-numeric stub output.** Per
the `feedback_dont_defer_hole_closure.md` adjacent reasoning: an
invalid port from a consumer stub is a configuration bug the
consumer needs to know about, but it should not break the user's
whole workflow (port resolution is upstream of every dev-server
operation). Warn loudly to stderr; continue with built-in.

**Decision: non-zero stub exit also falls through.** Same
rationale — port resolution is too critical to fail. Per Phase 2's
pinned non-zero-rc contract, the lib already emits
`zskills: scripts/dev-port.sh exited <rc>` on stderr; no extra
warning at the port.sh callsite is needed. The callsite simply
checks `ZSKILLS_STUB_RC == 0` to decide whether to honor stdout.

**Argument list.** `PROJECT_ROOT MAIN_REPO` — minimal, passes
the project-context the consumer needs to make a decision.

**No `eval`-style stdout handling.** `BASH_REMATCH` for numeric
validation; per `feedback_no_jq_in_skills.md`.

**Mirror discipline.** WI 4.6 covers `update-zskills`.

### Acceptance Criteria

- [ ] `grep -c 'zskills_dispatch_stub dev-port.sh'
      skills/update-zskills/scripts/port.sh` = 1.
- [ ] `test -x skills/update-zskills/stubs/dev-port.sh`.
- [ ] `grep -F 'dev-port.sh if missing'
      skills/update-zskills/SKILL.md` matches.
- [ ] `bash tests/test-port.sh` exits 0; PASS lines for the 5 new
      cases plus the existing tests.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills`
      empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1, Phase 2.

## Phase 5 — `start-dev.sh` (new) + convert `stop-dev.sh` and `test-all.sh` to failing stubs

### Goal

Three transformations — one new failing stub, two conversions from
"illusory implementations" to honest failing stubs.

### Work Items

(a) **NEW `start-dev.sh` failing stub.**

- [ ] 5.1 — **Create the stub source** at
      `skills/update-zskills/stubs/start-dev.sh`:
      ```bash
      #!/bin/bash
      # start-dev.sh -- Sanctioned way to start your dev server.
      #
      # CONFIGURE: replace the body below with your start command.
      # Contract: write each child PID to var/dev.pid (one per line)
      # on start. var/ is gitignored.
      #
      # Example:
      #   mkdir -p var
      #   npm run dev > var/dev.log 2>&1 &
      #   echo $! > var/dev.pid
      #
      # Pair: scripts/stop-dev.sh reads var/dev.pid and SIGTERMs each
      # PID. See .claude/skills/update-zskills/references/stub-callouts.md.

      echo "start-dev.sh: not configured. Edit scripts/start-dev.sh with your dev-start command (and write child PIDs to var/dev.pid)." >&2
      exit 1
      ```
- [ ] 5.2 — **`/update-zskills` Step D bullet:**
      > - Copy `start-dev.sh` if missing — sanctioned way to start a
      >   dev server. Initial install is a failing stub the user
      >   replaces with their start command (and a write to
      >   `var/dev.pid`).

(b) **CONVERT `stop-dev.sh` to failing stub.**

- [ ] 5.3 — **Drop the current implementation.** The current
      `scripts/stop-dev.sh` body is preserved in git history
      (`git show <pre-conversion-commit>:scripts/stop-dev.sh`) and
      consumers who want the historical behavior as a starting
      point can `git blame` / `git log` to recover it. We do NOT
      ship a `references/stop-dev-reference.sh` documentation
      copy — that creates a maintenance burden (R15 tension:
      tested → it's runnable infrastructure, not docs) without
      clear ownership. The `references/stub-callouts.md` doc
      describes the contract; consumers fill the body.
- [ ] 5.4 — **Replace `scripts/stop-dev.sh`** content with a failing
      stub paralleling start-dev:
      ```bash
      #!/bin/bash
      # stop-dev.sh -- Sanctioned way to stop your dev server.
      #
      # CONFIGURE: replace the body below with your stop logic.
      # Contract: read PIDs from var/dev.pid (one per line) and
      # SIGTERM each. Pair with scripts/start-dev.sh which writes
      # to var/dev.pid on start.
      #
      # NEVER use kill -9, killall, pkill, or fuser -k -- the
      # generic hook blocks them and they can hit other sessions'
      # processes.
      #
      # See .claude/skills/update-zskills/references/stub-callouts.md.

      echo "stop-dev.sh: not configured. Edit scripts/stop-dev.sh with your dev-stop command (read PIDs from var/dev.pid; kill -TERM each). See .claude/skills/update-zskills/references/stub-callouts.md." >&2
      exit 1
      ```
      Note: this overwrites the current `scripts/stop-dev.sh` —
      because the prerequisite plan kept `stop-dev.sh` at Tier-2
      (consumer `scripts/`), this IS the source-tree edit. Skip-if-
      exists semantics in `/update-zskills` ensure consumers who
      already have a customized `stop-dev.sh` are not overwritten.
- [ ] 5.5 — **Update `/update-zskills` Step D bullet** for
      `stop-dev.sh` (currently `skills/update-zskills/SKILL.md:906-908`):
      old text "the sanctioned way for agents to stop a dev server
      (SIGTERM to PIDs in `var/dev.pid`)…"; new text:
      > - Copy `stop-dev.sh` if missing — sanctioned way to stop a
      >   dev server. Initial install is a failing stub the user
      >   replaces (contract: read PIDs from `var/dev.pid`, SIGTERM
      >   each). Pair: `start-dev.sh`.
- [ ] 5.6 — **Update hook help-text** in
      `hooks/block-unsafe-generic.sh` (lines 159 and 177; verbatim
      current text contains `Use bash scripts/stop-dev.sh for your
      own dev server, or target a known PID with 'kill PID'
      directly.`). After Phase 5's conversion, `scripts/stop-dev.sh`
      is a failing stub by default — pointing users at it without
      acknowledging the configure-first step is a regression.
      Replace both occurrences with:
      > `Use bash scripts/stop-dev.sh (failing stub by default — edit it with your stop logic) to stop your dev server, or target a known PID with 'kill PID' directly.`
      Also update the related comment at line 156 / 174 prose if
      it pre-states the same recommendation. Mirror to
      `.claude/hooks/block-unsafe-generic.sh`.
- [ ] 5.7 — **Update `CLAUDE_TEMPLATE.md`** lines 7–23 (verified by
      research). Add a "to start" paragraph paralleling "to stop";
      reframe the prose to acknowledge the stub model. Verbatim
      before block (CLAUDE_TEMPLATE.md:7-15):
      ```markdown
      ## Dev Server

      ```bash
      {{DEV_SERVER_CMD}}
      ```

      The port is determined automatically by `{{PORT_SCRIPT}}`: ...

      **To stop this worktree's dev server, run `bash scripts/stop-dev.sh`.** It sends SIGTERM to the PIDs recorded in `var/dev.pid`. Contract: your `{{DEV_SERVER_CMD}}` must write each spawned child PID (one per line) to `var/dev.pid` on start, and should clear it on clean shutdown. `var/` is gitignored.
      ```
      After block (replace with):
      ```markdown
      ## Dev Server

      Run `bash scripts/start-dev.sh` to start the dev server and `bash scripts/stop-dev.sh` to stop it. Both ship as failing stubs that the consumer customizes; see the in-file comments for the contract. The pairing is: `start-dev.sh` runs `{{DEV_SERVER_CMD}}` and writes each spawned child PID (one per line) to `var/dev.pid`; `stop-dev.sh` reads `var/dev.pid` and SIGTERMs each. `var/` is gitignored.

      The port is determined automatically (8080 for the main repo; a deterministic per-worktree port otherwise). Run `bash .claude/skills/update-zskills/scripts/port.sh` to see your port. Override with `DEV_PORT=NNNN` env var, or with a `scripts/dev-port.sh` stub for project-wide custom logic (see `.claude/skills/update-zskills/references/stub-callouts.md`).
      ```
      Drop the `{{DEV_SERVER_CMD}}` codeblock at lines 9–11 (now
      consumed by start-dev.sh) and the `{{PORT_SCRIPT}}` placeholder.
      Pre-edit verification: run
      `grep -EF '{{PORT_SCRIPT}}|{{DEV_SERVER_CMD}}' skills/update-zskills/scripts/apply-preset.sh skills/update-zskills/SKILL.md`.
      Expected post-prerequisite: zero matches in apply-preset.sh's
      replacement list. **If the grep returns ≥ 1 match, abort
      this WI and surface as a prerequisite-plan miss** per
      `feedback_dont_defer_hole_closure.md` — do NOT patch
      CLAUDE_TEMPLATE.md to absorb leftover placeholders.

(c) **CONVERT `test-all.sh` to failing stub.**

- [ ] 5.8 — **Drop the current implementation.** Same rationale as
      5.3 — git history preserves the prior body; no
      `references/test-all-reference.sh` shipped.
- [ ] 5.9 — **Replace `scripts/test-all.sh`** content with a failing
      stub:
      ```bash
      #!/bin/bash
      # test-all.sh -- Run all test suites (unit + e2e + build).
      #
      # CONFIGURE: replace the body below with your test runner.
      # zskills skills (run-plan, verify-changes) invoke this when
      # `testing.full_cmd` resolves to `bash scripts/test-all.sh`.
      #
      # See .claude/skills/update-zskills/references/stub-callouts.md
      # for the contract; typical implementations orchestrate unit +
      # e2e + build (read testing.unit_cmd from
      # .claude/zskills-config.json, derive a dev-server port,
      # run e2e if the port is up, etc.). git history preserves
      # the prior shipped orchestrator if you want a starting
      # point.

      echo "test-all.sh: not configured. Edit scripts/test-all.sh with your test runner. See .claude/skills/update-zskills/references/stub-callouts.md." >&2
      exit 1
      ```
- [ ] 5.10 — **Add `/update-zskills` Step D bullet** for
      `test-all.sh`. Verified: Step D today (SKILL.md:895–910)
      lists `clear-tracking.sh`, `apply-preset.sh`,
      `stop-dev.sh` — and **no** `test-all.sh` bullet. The
      prerequisite plan's text on this is also conditional and
      unpinned, so this WI is unconditional regardless of the
      prereq's pre-state. Add after the existing bullets:
      > - Copy `test-all.sh` if missing — invoked by `/run-plan`,
      >   `/verify-changes`, etc. when `testing.full_cmd` is
      >   `bash scripts/test-all.sh`. Initial install is a failing
      >   stub the user replaces.
- [ ] 5.11 — **Skill-side test-all.sh callsite check + preset
      check.** Two greps:
      (a) `grep -rn 'scripts/test-all\|test-all.sh' skills/` — all
      hits should be NEVER admonitions / commentary, not defaults.
      (b) `grep -F 'scripts/test-all.sh' skills/update-zskills/scripts/apply-preset.sh`
      — must be **zero**. If `apply-preset.sh` injects
      `bash scripts/test-all.sh` as a default `testing.full_cmd`,
      fresh-install consumers hit the failing stub on their first
      `/run-plan` (silently broken UX).
      If either grep finds a default, that's a prerequisite-plan
      miss — flag, surface, do not patch here per
      `feedback_dont_defer_hole_closure.md`.
- [ ] 5.12 — **Update tests.** `tests/test-stop-dev.sh` currently
      tests the working `stop-dev.sh`. Replace with a single-case
      test that confirms `bash scripts/stop-dev.sh` exits 1 and
      stderr matches `not configured`. Same for any
      `tests/test-test-all.sh` if present.
- [ ] 5.13 — **Sweep `README.md`** for `test-all.sh` / `stop-dev.sh`
      references (research line 458 found
      `scripts/test-all.sh — meta test runner (unit + E2E + build
      tests)`). Update prose to:
      > - `test-all.sh` — failing-stub by default; consumer fills
      >   with their test orchestrator.
- [ ] 5.14 — **Mirror** all touched skills:
      `update-zskills` (Step D, references, stubs).

### Design & Constraints

**Why convert vs. keep as today.** Per the user instruction and
`feedback_no_premature_backcompat.md`: the current
`scripts/test-all.sh` ships with `{{E2E_TEST_CMD}}` literals that
**fail at runtime** (bash "command not found" → exit 127); the
current `scripts/stop-dev.sh` ships **functional** but assumes the
undocumented `var/dev.pid` contract and silently no-ops if absent.
Both pretend to work; failing stubs make the contract explicit.

**No `references/*-reference.sh` ships.** Earlier draft proposed
preserving the prior implementations as `references/`-dir
documentation. Dropped because: (1) tested → maintained code, not
docs (R15 tension); (2) `references/stub-callouts.md` is the
authoritative contract doc; (3) git history preserves prior bodies
for any consumer who wants them as a starting point.

**Skip-if-exists protects customized files.** `/update-zskills`
Step D's `if [ ! -f scripts/$X ]; then cp...; fi` semantics ensure
consumers with already-customized `stop-dev.sh`/`test-all.sh` are
**never overwritten** — the failing stub only lands on first
install. After first install, the stub IS the consumer's file.

**Hook help-text update (5.6).** The hook's pre-conversion message
recommends `bash scripts/stop-dev.sh` as the sanctioned kill path.
Post-conversion, that command exits 1 with `not configured`. WI
5.6 updates the help-text to flag the stub model
(`consumer-customizable stub; configure first per ...`) so a user
hitting the hook block in an unconfigured project sees the
configure step in the same message. The `kill PID` direct fallback
is preserved. This follows
`feedback_hook_skill_interaction.md`: when skills change, hook
static text must change too — don't relax the hook, fix the text.

**No new test for the stop-dev / test-all failing stubs** beyond a
single-line "exits 1, message matches". The stubs are trivial.

**Mirror discipline.** WI 5.14 covers all skill edits in this
phase.

### Acceptance Criteria

- [ ] `test -x skills/update-zskills/stubs/start-dev.sh`.
- [ ] `bash scripts/stop-dev.sh; rc=$?; [ "$rc" -eq 1 ]` and
      stderr matches `not configured`.
- [ ] `bash scripts/test-all.sh; rc=$?; [ "$rc" -eq 1 ]` and
      stderr matches `not configured`.
- [ ] `grep -F 'not configured' scripts/stop-dev.sh` matches
      (stable signal that conversion happened, not a line-count).
- [ ] `grep -F 'not configured' scripts/test-all.sh` matches.
- [ ] `grep -F 'start-dev.sh if missing'
      skills/update-zskills/SKILL.md` matches.
- [ ] `grep -F 'test-all.sh if missing'
      skills/update-zskills/SKILL.md` matches.
- [ ] `grep -F 'start-dev.sh' CLAUDE_TEMPLATE.md` matches.
- [ ] `grep -F 'failing-stub by default' README.md` matches (or
      equivalent prose anchor — implementer to choose).
- [ ] `bash tests/test-stop-dev.sh` exits 0 (now testing reference
      impl + stub-fail case).
- [ ] `grep -F 'failing stub by default' hooks/block-unsafe-generic.sh`
      ≥ 2 (one for each updated block-reason; lines 159 and 177).
- [ ] `diff hooks/block-unsafe-generic.sh .claude/hooks/block-unsafe-generic.sh`
      empty (mirror).
- [ ] `bash tests/run-all.sh` exits 0.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills`
      empty.

### Dependencies

Phase 1, Phase 2.

## Phase 6 — Hooks / CLAUDE_TEMPLATE / docs sweep + `briefing-extra.sh` decision

### Goal

Sweep remaining doc references; resolve the `briefing-extra.sh`
question explicitly.

### Work Items

- [ ] 6.1 — **README sweep.** `grep -nE
      'scripts/(test-all|stop-dev|start-dev|dev-port|post-create-worktree)'
      README.md`. For each match, ensure prose reflects the
      stub-by-default model. Phase 5.13 covered the line-458 hit;
      this WI is the broader sweep for any other mention.
- [ ] 6.2 — **CLAUDE_TEMPLATE.md verification.** Re-read lines
      1–40 and confirm the Phase 5.7 edits are coherent. Specifically:
      no orphan `{{PORT_SCRIPT}}` reference, no orphan
      `{{DEV_SERVER_CMD}}` codeblock, "to start" / "to stop" pair
      reads naturally, port-section references stub-callout convention.
- [ ] 6.3 — **`briefing-extra.sh` decision: DEFERRED.**
      **Rationale:** there is no current consumer demand for a
      briefing-extension seam. The convention is now formalized in
      `references/stub-callouts.md`, the dispatch helper is shipped
      and tested, and adding a future `briefing-extra.sh` callout
      is mechanical (insertion at end of `briefing.cjs`'s output
      assembly, one stub file, one test, one Step-D bullet — likely
      a single PR). Per `feedback_dont_defer_hole_closure.md`: this
      is NOT a deferred hole — there is no current bug or missing
      contract. It is a **deferred extension point** with a clear
      pattern to follow when a real need surfaces.

      Document this decision in `references/stub-callouts.md`
      under a "Future callouts" subsection as a single line so the
      next agent doesn't re-litigate the deferral itself:
      > - `briefing-extra.sh` — declined for now; revisit when
      >   first consumer demand surfaces.
- [ ] 6.4 — **`/update-zskills` step-D preview.** The Step D
      preview to the user (lines 880–882 reference the rename-list
      shown in Step C step 6) needs to include the four new stubs
      in its install report. Verify:
      `grep -A20 'Installed N scripts' skills/update-zskills/SKILL.md` —
      the report-line list is dynamic (`[list]`); no edit needed
      if the existing format auto-includes the new bullets. If
      it's hardcoded, extend.
- [ ] 6.5 — **Mirror** any touched skills (likely just
      `update-zskills` for the references update).

### Design & Constraints

**`briefing-extra.sh` deferral is principled, not lazy.** Phase 6.3
is explicit: there is no consumer demand, the seam is mechanical to
add later, the convention is now documented. This is the
distinction `feedback_dont_defer_hole_closure.md` draws between
"hole closure" (close it now) and "extension point" (add when
needed). Holes need closing because they're broken contracts;
extension points are speculation.

**No hook edits.** Phase 5.6 already concluded `block-unsafe-generic.sh`
help-text remains correct.

### Acceptance Criteria

- [ ] `grep -nE 'scripts/(test-all|stop-dev|start-dev)' README.md`
      — every match is in stub-aware prose.
- [ ] `grep -F '{{PORT_SCRIPT}}' CLAUDE_TEMPLATE.md` returns no
      matches.
- [ ] `grep -F 'briefing-extra' skills/update-zskills/references/stub-callouts.md`
      matches (decision recorded).
- [ ] **Every shipped stub references the canonical doc:**
      `for f in skills/update-zskills/stubs/*.sh; do grep -qF 'references/stub-callouts.md' "$f" || { echo "stub $f missing reference"; exit 1; }; done`
      — pins doc-string consistency between the stub headers and
      `references/stub-callouts.md`; future PRs that touch one
      without the other fail this gate.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1–5.

## Phase 7 — Close-out

### Goal

CHANGELOG entry, plan-index update, frontmatter flip.

### Work Items

- [ ] 7.1 — **CHANGELOG entry.** Insert at top of unreleased /
      current section (do NOT modify historical entries — same
      discipline as prerequisite plan Phase 6). The entry must
      flag the **silent-conversion caveat** for existing consumers
      (DA5): skip-if-exists protects their `stop-dev.sh` /
      `test-all.sh`, but those existing copies don't pair with the
      new `start-dev.sh` contract:
      ```
      - feat(stubs): formalize consumer stub-callout convention; add post-create-worktree.sh, dev-port.sh, start-dev.sh stubs; convert stop-dev.sh, test-all.sh to failing stubs. Existing consumers: your old stop-dev.sh / test-all.sh stay (skip-if-exists); to adopt the new start-dev.sh / stop-dev.sh pairing (start-dev writes var/dev.pid; stop-dev reads it), `rm scripts/start-dev.sh scripts/stop-dev.sh && /update-zskills` for the new templates, then customize.
      ```
- [ ] 7.2 — **Plan index.** If `plans/PLAN_INDEX.md` exists, add a
      row for `CONSUMER_STUB_CALLOUTS_PLAN.md` in the same style
      as siblings (move from "Active" to "Complete" if those
      categories exist).
- [ ] 7.3 — **Frontmatter flip:** `status: complete` and add
      `completed: <date>` line.

### Acceptance Criteria

- [ ] `grep -F 'consumer stub-callout convention' CHANGELOG.md`
      matches (loose pin tolerates prefix re-framing).
- [ ] `head -10 plans/CONSUMER_STUB_CALLOUTS_PLAN.md` shows
      `status: complete` and `completed:` lines.
- [ ] `grep -q 'CONSUMER_STUB_CALLOUTS' plans/PLAN_INDEX.md`
      succeeds OR file absent.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1–6.

## Plan Quality

**Drafting process:** /draft-plan with adversarial review
**Convergence:** converged in round 2 (all 6 round-2 polish items addressed inline)
**Remaining concerns:** None blocking. Phase 5 has 14 WIs across 3 transformations; reviewer suggested splitting 5a/5b but the conversion is a coherent unit and the dropped reference-impls reduce per-WI burden.

**Mode-agnosticism (clarification of DA14).** The "Landing mode: PR" hint at the top of this plan controls only how `/run-plan` lands these commits — it does not propagate to runtime behavior. The skill this plan delivers (dispatch helper, new stubs, failing-stub conversions, hook help-text) operates identically under any landing mode at consumer runtime. The Phase 1 staleness gate is also mode-agnostic: every anchor is filesystem state (file moves, frontmatter `status: complete`, CHANGELOG entry written by prerequisite Phase 6 WI 6.1, `tests/run-all.sh` `CLAUDE_PROJECT_DIR` export) — none are mode-specific. The prerequisite plan (`SCRIPTS_INTO_SKILLS_PLAN`) writes its CHANGELOG entry as an explicit Phase 6 work item, so that anchor fires regardless of which mode lands the prerequisite.

### Round History
| Round | Reviewer Findings | Devil's Advocate Findings | Resolved |
|-------|-------------------|---------------------------|----------|
| 1     | 16                | 18                        | 34/34    |
| 2     | 6 (R2.x convergence-check)  | combined with reviewer  | All round-1 fixes verified landed; 1 new major (N1, lib silent-fail) + 5 new minors (N2-N6) — all fixed in this round. Verdict: Converged. |

#### Round 1 disposition

- **R1 / DA1** (CRITICAL, port.sh `_ZSK_REPO_ROOT` unset): FIXED — Phase 4 WI 4.1 now uses `${CLAUDE_PROJECT_DIR:-$PROJECT_ROOT}` for lib path and bare `$PROJECT_ROOT` as dispatch arg; verbatim, no implementer choice. Verified `port.sh:27` unsets `_ZSK_REPO_ROOT`; `PROJECT_ROOT` set at line 12 and never unset.
- **R2** (Phase 1 anchor symmetry): FIXED — added `clear-tracking.sh` present-anchor; symmetric three-pair coverage.
- **R3** (CHANGELOG grep brittle): FIXED — switched from `grep -F` to tolerant `grep -E 'Tier.?1.*owning skills?|move.*scripts.*into.*skills|relocate.*scripts.*under.*skills'`.
- **R4** (halt-path AC fragile): FIXED — removed live-tree `mv CHANGELOG.md` test; trust per-WI checks + Design verification.
- **R5 / DA7** (`var/.zskills-stub-noted-<stub>` location): FIXED — moved to `.zskills/stub-notes/<stub>.noted` per `feedback_claude_dir_prompts.md`.
- **R6** (lib non-zero rc not pinned): FIXED — lib emits `zskills: scripts/<name> exited <rc>` on stderr; documented in Phase 2 Design and `references/stub-callouts.md`; Phase 4 Design simplified accordingly.
- **R7 / DA-coordination** (WI 5.10 conditional): FIXED — unconditional add of test-all.sh bullet; verified Step D today has no test-all.sh entry.
- **R8 / DA6** (CRITICAL, hook help-text): FIXED — Phase 5 WI 5.6 rewritten to actively edit `hooks/block-unsafe-generic.sh` lines 159 and 177, plus mirror; AC added (`grep -F 'consumer-customizable stub'` ≥ 2).
- **R9** (halt-message refine-plan recommendation): FIXED — trimmed to optional aside.
- **R10** (CLAUDE_TEMPLATE.md verification): FIXED — pre-edit grep on apply-preset.sh + SKILL.md; abort-if-leftover surfacing path documented.
- **R11** (rc 9 collision): JUSTIFIED — added Design note: spot-checked /run-plan + tests, no special-casing of rc 9.
- **R12** (briefing-extra deferral sketch): FIXED — trimmed to one-line entry in `references/stub-callouts.md`.
- **R13** (multi-invocation test missing): FIXED — added test case 7 (`multiple-invocations-clean-state`).
- **R14** (post-create-worktree args missing MAIN_ROOT): FIXED — added `$6 MAIN_ROOT` to positional list; updated stub doc.
- **R15** (reference-impl tension docs vs runnable): FIXED — dropped `references/*-reference.sh` shipping entirely; git history preserves prior bodies.
- **R16** (phase count): JUSTIFIED — kept 7 (precedent: SCRIPTS_INTO_SKILLS_PLAN). Phase 5 reduced in scope by R15 fix.
- **DA1** = R1 (resolved jointly).
- **DA2** (Step D copy mechanism for `stubs/`): FIXED — new WI 2.4 explicitly extends Step D's source-dir list to include `$PORTABLE/skills/update-zskills/stubs/`; AC added.
- **DA3** (Phase 1 missing CLAUDE_PROJECT_DIR anchor): FIXED — added `grep -F 'export CLAUDE_PROJECT_DIR' tests/run-all.sh` to WI 1.2.
- **DA4** (rollback semantics contradiction): JUSTIFIED — added Design note in Phase 3 documenting the deliberate write-failure-vs-stub-failure distinction; flagged to be added to `references/stub-callouts.md`.
- **DA5** (silent conversion for existing consumers): FIXED — Phase 7 CHANGELOG entry expanded to flag the caveat with explicit upgrade path.
- **DA6** = R8 (resolved jointly).
- **DA7** = R5 (resolved jointly).
- **DA8** (port stdout edge cases): FIXED — Phase 4 WI 4.1 trims whitespace, requires `^[1-9][0-9]+$` (rejects 0/leading-zero/embedded newlines).
- **DA9** (stub timeout unaddressed): FIXED — added Phase 2 Design note: no library-default timeout (variance too wide); per-callsite `timeout 10s` documented as optional.
- **DA10** (stdout/stderr collision): FIXED — added Phase 2 Design note: stderr passthrough by default; future `--stdout=stream` flag documented as a follow-on extension.
- **DA11** (apply-preset.sh check): FIXED — Phase 5 WI 5.11 expanded to grep apply-preset.sh for `scripts/test-all.sh` defaults.
- **DA12** (Phase 5 size): FIXED in part — dropped reference-impl WIs (R15) simplified 5.3 / 5.8 in scope; final count is 14 WIs (5.1–5.14). Did not split into 5a/5b — the conversion is a coherent unit and splitting would fragment the CHANGELOG entry.
- **DA13** (apply-preset.sh placeholder check): FIXED — folded into R10 fix (pre-edit grep widened to apply-preset.sh).
- **DA14** (cherry-pick mode lacks CHANGELOG): NOT REPRODUCED — the prerequisite plan's Phase 6 WI 6.1 explicitly edits `CHANGELOG.md` like any other WI; that edit lands regardless of mode (cherry-pick / PR / direct). The DA's framing ("landing mode determines whether CHANGELOG gets written") was incorrect — landing mode controls *how* commits are organized into worktrees / PRs / branches, not *what* WIs do. The skill this plan delivers, and the staleness gate that protects it, are both mode-agnostic. No fix needed; clarified in Plan Quality "Mode-agnosticism" note.
- **DA15** (`_STUB_LIB` env leak): FIXED — added `unset _STUB_LIB` after both callsites (Phase 3 and Phase 4).
- **DA16** (`wc -l` AC brittle): FIXED — replaced with stable `grep -F 'not configured'` ACs.
- **DA17** (heredoc-in-bash-c quoting): JUSTIFIED — removed via R4 fix (the live-tree halt-path AC was the only place this nesting was prescribed).
- **DA18** (CHANGELOG entry exact-string AC): FIXED — Phase 7 AC loosened to `grep -F 'consumer stub-callout convention'`.
