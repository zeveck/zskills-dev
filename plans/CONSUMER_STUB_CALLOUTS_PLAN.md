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
| 1 — Staleness gate (halt if SCRIPTS_INTO_SKILLS_PLAN not landed) | ✅ Done | `942c4f4` | Regression-guard; all anchors pass |
| 2 — Stub-callout convention + sourceable dispatch helper | ✅ Done | `4f457a3` | Lib + ref + 8-case test + Step D + mirror; 951/951 tests |
| 3 — `post-create-worktree.sh` callout in `create-worktree.sh` | ✅ Done | `698c6e6` | Callout wired + stub + 3-case test + lib `set -e` safety fix; 1016/1016 |
| 4 — `dev-port.sh` callout in `port.sh` | ✅ Done | `c632391` | Callout + 6 test cases + Tier-1 hash regen; 1075/1075 |
| 5 — `start-dev.sh` (new) + convert `stop-dev.sh` / `test-all.sh` to failing stubs | ✅ Done | `f8ab398` | start-dev stub + 2 in-place conversions + hook help + CLAUDE_TEMPLATE + README + test-stop-dev deletion; 1066/1066 |
| 6 — Hooks / CLAUDE_TEMPLATE / docs sweep + `briefing-extra.sh` decision | 🟡 In Progress |  |  |
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
      we use a tolerant regex. Each alternation requires the
      "Tier" keyword to avoid matching unrelated CHANGELOG prose
      that happens to mention "move scripts" (DA16 fix):
      ```bash
      grep -E 'Tier.?1.*owning skills?|move.*Tier.?1.*into.*skills|relocate.*Tier.?1.*skills' CHANGELOG.md \
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

**Post-prerequisite-landing reality.** As of refine-round-1
(post-PRs #94–#100 + PR #88), all 1.1–1.3 anchors pass against
current main. Phase 1 functions as a **regression guard** (catches
a future re-rolled or partially-rolled-back prereq), not as a
discovery check. The HALT path will not fire on first invocation
of `/run-plan` against a clean tree; that is intentional.

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
      `plans/SCRIPTS_INTO_SKILLS_PLAN.md`. (Already passes;
      regression guard.)
- [ ] WI 1.2 multi-anchor compound test passes (rc 0). (Already
      passes; regression guard against future partial rollback.)
- [ ] WI 1.3 grep matches the tightened CHANGELOG alternation
      (passes against current `CHANGELOG.md:6`
      `refactor(scripts): move Tier-1 scripts into owning skills`).
- [ ] **No live-tree halt-path test.** Per CLAUDE.md "Never modify
      the working tree to check if a failure is pre-existing" —
      do NOT rename `CHANGELOG.md` or any source file to test the
      halt path. The shell-mechanics of `exit 1` halting `/run-plan`
      are already verified in the Design ("Halt mechanism (verified)"
      above); we trust that and the per-WI checks above. If
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
      >    arguments (per-stub; see canonical table). The dispatcher
      >    consumes a single `--` discriminator (required at every
      >    callsite) before forwarding the remainder verbatim — a
      >    literal `--` argument inside the stub's `$@` is preserved.
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
      >    file is touched after the first note). If the marker
      >    write fails (read-only fs), the note is suppressed —
      >    this avoids per-invocation noise on systems where the
      >    marker can't be persisted.
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
          # Suppress the note when marker write fails (e.g. read-only fs)
          # to avoid per-invocation noise on systems that can't persist.
          if mkdir -p "$notes_dir" 2>/dev/null && touch "$marker" 2>/dev/null; then
            echo "zskills: invoking consumer stub scripts/$name (one-time note; see .claude/skills/update-zskills/references/stub-callouts.md)" >&2
          fi
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
      `tests/test-create-worktree.sh:828-836` **FIX_NN-style
      temp-fixture pattern**: `FIX_N="/tmp/<test-prefix>-fixture-$$"`,
      `rm -rf "$FIX_N"`, `mkdir -p "$FIX_N/scripts"`, `git init
      --quiet -b main "$FIX_N"`, `git -C "$FIX_N" config user.email/name`,
      `cp "$REPO_ROOT/skills/<owner>/scripts/<helper>.sh" "$FIX_N/scripts/"`,
      `chmod +x`, then `cd "$FIX_N" && bash "$SCRIPT" ...`. Cases:
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
      8. **Literal `--` in stub args (DA10):** call dispatcher with
         `... -- foo -- bar`; verify the stub's `$@` is `(foo, --, bar)`
         (the dispatcher consumes only the FIRST `--`, the second is
         forwarded verbatim).
      Add `tests/test-stub-callouts.sh` to `tests/run-all.sh`.
- [ ] 2.4 — **Extend `/update-zskills` Step D to copy from
      `stubs/`.** New stubs (post-create-worktree.sh, dev-port.sh,
      start-dev.sh) ship at
      `skills/update-zskills/stubs/<name>.sh` (a new directory,
      parallel to `scripts/` — for consumer-installable failing-stub
      / no-op templates). Step D currently only copies "from
      `$PORTABLE/scripts/`" (verified at SKILL.md:897). Edit Step
      D's copy-loop / source-dir list to **also** copy missing
      files from `$PORTABLE/skills/update-zskills/stubs/` to the
      consumer's `scripts/` (skip-if-exists). Document this dual
      source explicitly in the Step D prose:
      > Copy missing scripts from `$PORTABLE/scripts/` and from
      > `$PORTABLE/skills/update-zskills/stubs/` to `scripts/`
      > (verify executable bit is preserved). The `stubs/` dir
      > holds NEW consumer-customizable failing-stub / no-op
      > templates (post-create-worktree.sh, dev-port.sh,
      > start-dev.sh); `scripts/` holds the existing zskills-managed
      > Tier-2 templates (stop-dev.sh, test-all.sh — kept at
      > `scripts/` for continuity with prior installs; their
      > bodies become failing stubs in Phase 5 but their source
      > location does not move).
      AC: `grep -F 'skills/update-zskills/stubs/' skills/update-zskills/SKILL.md` ≥ 1.
- [ ] 2.5 — **Mirror** `update-zskills`:
      ```bash
      bash scripts/mirror-skill.sh update-zskills
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

**`stubs/` vs `scripts/` source-of-truth (DA5).** Two source
directories, one canonical-source rule per stub:

- `skills/update-zskills/stubs/` — NEW failing-stub / no-op source
  templates introduced by this plan: `post-create-worktree.sh`,
  `dev-port.sh`, `start-dev.sh`.
- `scripts/` (top-level) — existing Tier-2 zskills-managed
  templates that the prerequisite kept at the top-level `scripts/`
  per `skills/update-zskills/SKILL.md:960` (which excludes them
  from STALE_LIST): `stop-dev.sh`, `test-all.sh`. Phase 5
  OVERWRITES their content in place; their source location does
  not move. Their Step D copy bullets continue to read from
  `$PORTABLE/scripts/`.

Step D never reads from both directories for the same name. New
stubs go in `stubs/`; the two pre-existing Tier-2 templates stay
at `scripts/`. If a future stub needs to be added, it goes in
`stubs/` (the canonical home for new consumer-installable
templates). Documented in `references/script-ownership.md` via
Phase 7 close-out.

**`--` discriminator pinned (DA10).** The dispatcher's `--`
separator is **required** at every callsite (every existing
call-site already passes it; tests confirm with case 8). The lib
consumes only the first `--` and forwards subsequent tokens
verbatim, so a stub that legitimately needs a `--` in its own
`$@` is unaffected. Documented in `references/stub-callouts.md`
under the contract.

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
WI 2.5 mirrors via `bash scripts/mirror-skill.sh update-zskills`
per the prerequisite plan's convention. Inline `rm -rf
.claude/skills/<name>` is blocked by
`hooks/block-unsafe-generic.sh:217-222` (RM_RECURSIVE regex +
is_safe_destruct require literal `/tmp/`); `mirror-skill.sh`
(PR #88) avoids the gate via per-file `rm` and `find -print0`.

**First-run marker scope and read-only-fs handling (DA9).**
Markers live at `.zskills/stub-notes/<stub>.noted` (per project;
`.zskills/` is the existing zskills-managed directory and is the
right home for agent-written ephemeral state per
`feedback_claude_dir_prompts.md` — `.claude/` writes trigger
permission prompts, `.zskills/` does not). The lib only emits the
first-run note if the marker write succeeds (`mkdir -p && touch`
under `2>/dev/null` and a guarded `if`); on read-only fs the note
is silently suppressed to avoid per-invocation noise. We
deliberately do NOT write under `var/` — zskills' own `.gitignore`
does not list `var/`, and consumer projects vary; using
`.zskills/` avoids creating a surprise directory in foreign
projects.

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
      8 cases above (including multi-invocation clean-state and the
      DA10 literal-`--` case).
- [ ] `grep -c 'test-stub-callouts.sh' tests/run-all.sh` ≥ 1.
- [ ] **Test sources lib via source-tree path, not via mirror:**
      `! grep -F '$CLAUDE_PROJECT_DIR' tests/test-stub-callouts.sh`
      (zero matches — test must source the lib via
      `$REPO_ROOT/skills/update-zskills/scripts/zskills-stub-lib.sh`
      so it works in fresh `tests/run-all.sh` runs without depending
      on `.claude/skills/` mirror state).
- [ ] `grep -F 'skills/update-zskills/stubs/' skills/update-zskills/SKILL.md`
      ≥ 1 (Step D extended to copy from `stubs/`).
- [ ] **Lib-missing stderr warning wired at both callsites
      (DA15 — split per-file):**
      `grep -c -F 'stub-lib missing' skills/create-worktree/scripts/create-worktree.sh` ≥ 1
      AND
      `grep -c -F 'stub-lib missing' skills/update-zskills/scripts/port.sh` ≥ 1
      (regression guard against future edits dropping the warning
      from one site while doubling it in the other).
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
      `tail -25 skills/create-worktree/scripts/create-worktree.sh` —
      the final block today is at lines 336–355). Verbatim before
      block (current `skills/create-worktree/scripts/create-worktree.sh:336-355`):
      ```bash
      # WI 1a.11 — Rollback on .zskills-tracked write failure.
      if ! printf '%s\n' "$PIPELINE_ID" > "$WT_PATH/.zskills-tracked"; then
        echo "create-worktree: post-create write failed — worktree rolled back" >&2
        git -C "$MAIN_ROOT" worktree remove --force "$WT_PATH" 1>&2 || true
        exit 8
      fi

      if [ -n "$PURPOSE" ]; then
        if ! printf '%s\n' "$PURPOSE" > "$WT_PATH/.worktreepurpose"; then
          echo "create-worktree: post-create write failed — worktree rolled back" >&2
          git -C "$MAIN_ROOT" worktree remove --force "$WT_PATH" 1>&2 || true
          exit 8
        fi
      fi

      # ──────────────────────────────────────────────────────────────────
      # WI 1a.12 — Final stdout: exactly one line with the path.
      # ──────────────────────────────────────────────────────────────────
      printf '%s\n' "$WT_PATH"
      exit 0
      ```
      Insert **after the `.worktreepurpose` block, before the
      `# WI 1a.12` divider line**:
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
      Edit `skills/update-zskills/SKILL.md` Step D (heading at L895,
      body at 897-906; verify via `grep -nE '#### Step D|Copy.*if missing' skills/update-zskills/SKILL.md`).
      After the existing `stop-dev.sh` and `test-all.sh` bullets,
      add:
      > - Copy `post-create-worktree.sh` if missing — invoked by the
      >   `/create-worktree` skill's worktree-creation script after a
      >   successful create. Stub is a documented no-op; consumer
      >   replaces with setup steps (cp `.env.local`, `npm install`,
      >   etc.). See `.claude/skills/update-zskills/references/stub-callouts.md`.
- [ ] 3.3 — **Create the stub source** at
      `skills/update-zskills/stubs/post-create-worktree.sh`. New
      directory `skills/update-zskills/stubs/` (parallel to
      `scripts/`, holds NEW consumer-installable failing-stub /
      no-op templates per Phase 2 Design canonical-source rule).
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
      Three cases against a fake consumer project. Mirror the
      `tests/test-create-worktree.sh:828-836` **FIX_NN-style
      temp-fixture pattern**: `FIX_N="/tmp/<test-prefix>-fixture-$$"`,
      `mkdir -p "$FIX_N/scripts"`, `git init --quiet -b main "$FIX_N"`,
      `cp "$REPO_ROOT/skills/create-worktree/scripts/<helper>.sh"
      "$FIX_N/scripts/"`, `chmod +x`, install the stub-lib path,
      then `cd "$FIX_N" && bash "$SCRIPT" --pipeline-id ...`:
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
- [ ] 3.5 — **Mirror** `create-worktree` and `update-zskills`:
      ```bash
      bash scripts/mirror-skill.sh create-worktree
      bash scripts/mirror-skill.sh update-zskills
      ```

### Design & Constraints

**Insertion point verification.** The verbatim 20-line before-block
in WI 3.1 is from the **post-prerequisite-plan** path
(`skills/create-worktree/scripts/create-worktree.sh`). The drafter
verified this against the current
`skills/create-worktree/scripts/create-worktree.sh` (lines 336–355);
the SCRIPTS_INTO_SKILLS_PLAN's Phase 3a moved the file via
`git mv` without rewriting the tail, so the verbatim block is
preserved. The `...` ellipses do **not** appear in the verbatim
before-block in this WI — every line is quoted in full. If the
prerequisite plan rewrote the tail unexpectedly, `/refine-plan`
flags it; otherwise the insertion point matches.

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
write-failure path (line 340); rc 9 is the next free slot.
Spot-checked downstream: `/run-plan` failure protocol uses generic
non-zero handling, no special-case for rc 9; tests treat any
non-zero as failure.

**Failure-semantics contrast with neighboring blocks (DA4).** The
`.zskills-tracked` and `.worktreepurpose` write-failure paths
(lines 336–350) destroy the worktree via
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
`update-zskills/`; both mirror in WI 3.5 via `mirror-skill.sh`.
Inline `rm -rf .claude/skills/<name>` is blocked by
`hooks/block-unsafe-generic.sh:217-222`; `mirror-skill.sh`
(PR #88) avoids the gate via per-file `rm` and `find -print0`.

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
      path; verify with `cat -n skills/update-zskills/scripts/port.sh`
      — the script is 61 newline-terminated lines).

      **Upstream context (do NOT modify; lines 24-43 are the
      runtime config-read block added by prereq Phase 4 / PR #98):**
      ```
      [lines 24-43: BASH_REMATCH against .claude/zskills-config.json
       extracts dev_server.main_repo_path → MAIN_REPO and
       dev_server.default_port → DEFAULT_PORT, then unsets the
       _ZSK_REPO_ROOT/_ZSK_CFG temporaries at line 43. Untouched
       by this WI.]
      ```

      Verbatim before block (current
      `skills/update-zskills/scripts/port.sh:45-55`):
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

      After block (insert the consumer-callout block at line 50,
      between the DEV_PORT exit and the main-repo block):
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

      **Note (verified against current port.sh).** `port.sh:18` sets
      `PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
      (the script is invoked from the consumer repo via the shipped
      `.claude/skills/` tree, so the in-scope project root is taken
      from git, not the script location). `port.sh:43` does
      `unset _ZSK_REPO_ROOT _ZSK_CFG`. At the insertion point
      (line 50), `_ZSK_REPO_ROOT` is empty — but it WAS briefly
      bound at line 28 inside the runtime config-read block, and
      the lifetime is contained between L28 and L43. Use
      `${CLAUDE_PROJECT_DIR:-$PROJECT_ROOT}` for the lib path and
      bare `"$PROJECT_ROOT"` as the dispatch arg. **Do not redeclare
      `_ZSK_REPO_ROOT`** inside the inserted callout block —
      port.sh L28+L43 already creates and unsets that name inside
      the upstream runtime config-read block, and re-using it would
      shadow / leak across a load-bearing scope boundary.
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
- [ ] 4.6 — **Mirror** `update-zskills`:
      ```bash
      bash scripts/mirror-skill.sh update-zskills
      ```

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

**Mirror discipline.** WI 4.6 covers `update-zskills` via
`mirror-skill.sh` (hook-compatible per-file rm).

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
- [ ] 5.2 — **`/update-zskills` Step D bullet:** add after the
      existing `stop-dev.sh` (901-903) and `test-all.sh` (904-906)
      bullets:
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
- [ ] 5.4 — **Replace `scripts/stop-dev.sh`** content (in place;
      `stop-dev.sh` stays at top-level `scripts/` per Phase 2
      Design canonical-source rule and SKILL.md:960's STALE_LIST
      exclusion) with a failing stub paralleling start-dev:
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
      `stop-dev.sh` (currently `skills/update-zskills/SKILL.md:901-903`).
      The current bullet reads:
      > - Copy `stop-dev.sh` if missing — the sanctioned way for agents to stop
      >   a dev server (SIGTERM to PIDs in `var/dev.pid`). Keeps the generic
      >   hook's kill blocks intact while giving the agent a legitimate path.
      Replace with:
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
      Mirror to `.claude/hooks/block-unsafe-generic.sh`.
- [ ] 5.7 — **Update `CLAUDE_TEMPLATE.md`** Dev Server section
      (`## Dev Server` heading at L18; section spans L18-28
      verified by Read of the current template).

      **Pre-edit verification gates (F5 fix — split per token):**
      ```bash
      # PORT_SCRIPT must be absent everywhere (gone since prereq).
      grep -F '{{PORT_SCRIPT}}' skills/update-zskills/scripts/apply-preset.sh \
                                skills/update-zskills/SKILL.md \
                                CLAUDE_TEMPLATE.md
      # Expected: zero matches. If ≥ 1 match, abort and surface as
      # a prerequisite-plan miss.

      # DEV_SERVER_CMD must be absent from apply-preset.sh ONLY.
      # SKILL.md:323 has a documentation row (placeholder-mapping
      # table) that is intentional and MUST NOT trigger abort.
      grep -F '{{DEV_SERVER_CMD}}' skills/update-zskills/scripts/apply-preset.sh
      # Expected: zero matches. ≥ 1 match → prereq miss → abort.
      ```
      Both gates already pass on the current tree (regression
      guards). If a gate fires, surface as a prerequisite-plan
      miss per `feedback_dont_defer_hole_closure.md` — do NOT
      patch CLAUDE_TEMPLATE.md to absorb leftover placeholders.

      **Verbatim before-block (CLAUDE_TEMPLATE.md:18-28):**
      ```markdown
      ## Dev Server

      ```bash
      {{DEV_SERVER_CMD}}
      ```

      The port is determined automatically — run `bash .claude/skills/update-zskills/scripts/port.sh` to see it. **8080** for the main repo (`{{MAIN_REPO_PATH}}`), a **deterministic unique port** for each worktree (derived from the project root path). Override with `DEV_PORT=NNNN` env var if needed.

      **To stop this worktree's dev server, run `bash scripts/stop-dev.sh`.** It sends SIGTERM to the PIDs recorded in `var/dev.pid`. Contract: your `{{DEV_SERVER_CMD}}` must write each spawned child PID (one per line) to `var/dev.pid` on start, and should clear it on clean shutdown. `var/` is gitignored.

      **NEVER use `kill -9`, `killall`, `pkill`, or `fuser -k` to stop processes.** These can kill container-critical processes or disrupt other sessions' dev servers and E2E tests. Do not reach for `lsof -ti :<port> | xargs kill` either — it's the same anti-pattern under a different spelling. If a port is busy from another session's process, check with `lsof -i :<port>` and ask the user to stop it manually.
      ```

      **After-block (replace L18-28 with):**
      ```markdown
      ## Dev Server

      Run `bash scripts/start-dev.sh` to start the dev server and `bash scripts/stop-dev.sh` to stop it. Both ship as failing stubs that the consumer customizes (see in-file comments for the contract). The pairing: `start-dev.sh` runs `{{DEV_SERVER_CMD}}` and writes each spawned child PID (one per line) to `var/dev.pid`; `stop-dev.sh` reads `var/dev.pid` and SIGTERMs each. `var/` is gitignored.

      The port is determined automatically (8080 for the main repo `{{MAIN_REPO_PATH}}`; a deterministic per-worktree port otherwise). Run `bash .claude/skills/update-zskills/scripts/port.sh` to see your port. Override with `DEV_PORT=NNNN` env var, or with a `scripts/dev-port.sh` stub for project-wide custom logic (see `.claude/skills/update-zskills/references/stub-callouts.md`).

      **NEVER use `kill -9`, `killall`, `pkill`, or `fuser -k` to stop processes.** These can kill container-critical processes or disrupt other sessions' dev servers and E2E tests. Do not reach for `lsof -ti :<port> | xargs kill` either — it's the same anti-pattern under a different spelling. If a port is busy from another session's process, check with `lsof -i :<port>` and ask the user to stop it manually.
      ```

      The after-block preserves: (a) `{{MAIN_REPO_PATH}}` placeholder
      for apply-preset.sh substitution, (b) `{{DEV_SERVER_CMD}}`
      placeholder (now inlined in the start-dev.sh prose), and
      (c) the L28 kill-9 paragraph verbatim. Do NOT touch the
      worktree-rules `.landed` heredoc section at L96-114 (it
      contains `{{TIMEZONE}}` at L107 — DA4 regression guard).

(c) **CONVERT `test-all.sh` to failing stub.**

- [ ] 5.8 — **Drop the current implementation.** Same rationale as
      5.3 — git history preserves the prior body; no
      `references/test-all-reference.sh` shipped.
- [ ] 5.9 — **Replace `scripts/test-all.sh`** content (in place;
      stays at top-level `scripts/` per Phase 2 Design canonical-
      source rule and SKILL.md:960 STALE_LIST exclusion) with a
      failing stub:
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
- [ ] 5.10 — **Update `/update-zskills` Step D bullet for
      `test-all.sh`.** The current bullet at SKILL.md:904-906 reads:
      > - Copy `test-all.sh` if missing — consumer-customizable test runner
      >   template; placeholders such as `{{E2E_TEST_CMD}}` are filled in by
      >   the consumer with their own test commands.
      Replace with:
      > - Copy `test-all.sh` if missing — invoked by `/run-plan`,
      >   `/verify-changes`, etc. when `testing.full_cmd` is
      >   `bash scripts/test-all.sh`. Initial install is a failing
      >   stub the user replaces.
      (This is a REPLACE of the existing bullet, not an unconditional
      ADD — the prereq plan landed a `test-all.sh` bullet at
      904-906 that the original draft of WI 5.10 missed.)
- [ ] 5.11 — **Skill-side test-all.sh callsite check + preset
      check (regression guards).** Two greps:
      (a) `grep -rn 'scripts/test-all\|test-all.sh' skills/` — all
      hits should be NEVER admonitions / commentary, not defaults.
      (b) `grep -F 'scripts/test-all.sh' skills/update-zskills/scripts/apply-preset.sh`
      — must be **zero**. **Already passes as of refine-round-1**
      (apply-preset.sh has zero hits for this string today). This
      is a **regression guard**, not a discovery check: if a future
      apply-preset.sh edit re-introduces `bash scripts/test-all.sh`
      as a default `testing.full_cmd`, fresh-install consumers
      would hit the failing stub on their first `/run-plan`
      (silently broken UX). Halt and surface as a prerequisite-plan
      miss per `feedback_dont_defer_hole_closure.md`; do not patch
      here.
- [ ] 5.12 — **Update tests for stop-dev.sh and test-all.sh
      conversions.** Today `tests/test-stop-dev.sh` runs 7 verified
      behavioral tests against the working `scripts/stop-dev.sh`
      (no-PID, live-PID, dead-PID, SIGTERM-ignoring, blank/non-
      numeric, empty-PID-file, multi-PID — all 7 currently pass).
      After WI 5.4 lands, `scripts/stop-dev.sh` becomes a failing
      stub the consumer customizes; the 7 behavioral tests no
      longer apply to anyone's runtime (consumers who fill in
      their own stop logic do so in their own repos, where zskills
      doesn't run their tests). Per
      `feedback_no_premature_backcompat.md` (zskills doesn't test
      consumer code) and DA7's analysis:

      Action:
      - **Delete `tests/test-stop-dev.sh`** entirely.
      - **Remove its line from `tests/run-all.sh`** (the test
        invocation entry).
      - The 7 behavioral tests remain in git history if any
        consumer wants to copy them as a starting point for their
        own customized stop-dev.sh tests.
      - If `tests/test-test-all.sh` exists, delete it under the
        same rationale.

      No replacement single-case stub-fail test ships — the stub is
      trivial (3 lines of body), git history records its content,
      and `grep -F 'not configured' scripts/stop-dev.sh` (an AC
      below) verifies the conversion happened.
- [ ] 5.13 — **Sweep `README.md`** for `test-all.sh` / `stop-dev.sh`
      references (research line 458 found
      `scripts/test-all.sh — meta test runner (unit + E2E + build
      tests)`). Update prose to:
      > - `test-all.sh` — failing-stub by default; consumer fills
      >   with their test orchestrator.
- [ ] 5.14 — **Mirror** all touched skills:
      ```bash
      bash scripts/mirror-skill.sh update-zskills
      ```

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
(`failing stub by default — edit it with your stop logic`) so a
user hitting the hook block in an unconfigured project sees the
configure step in the same message. The `kill PID` direct fallback
is preserved. This follows
`feedback_hook_skill_interaction.md`: when skills change, hook
static text must change too — don't relax the hook, fix the text.

**Phrasing standardized on "failing stub by default" (F10).** The
WI 5.6 verbatim text, the README sweep target prose (5.13), and
the AC below all use the same string. Earlier draft language
("consumer-customizable stub") has been replaced for consistency
with the AC `grep -F 'failing stub by default' ...`.

**Test-deletion rationale (F11/DA7).** zskills doesn't test
consumer code; once `scripts/stop-dev.sh` becomes a failing stub
the consumer customizes, the 7 behavioral tests in
`tests/test-stop-dev.sh` are testing nothing zskills-relevant
(they currently test the about-to-be-replaced working
implementation). Delete the file rather than degrade it to a
single trivial assertion. Same for any pre-existing
`tests/test-test-all.sh`.

**`{{TIMEZONE}}` and worktree-rules section preserved (DA4).** WI
5.7 edits ONLY the `## Dev Server` section at L18-28. The
worktree-rules `.landed` heredoc section at L96-114 (which
contains `{{TIMEZONE}}` at L107) MUST NOT be touched by this WI.
Phase 6.2 verifies `grep -F '{{TIMEZONE}}' CLAUDE_TEMPLATE.md`
returns exactly 1 match as a regression guard.

**Mirror discipline.** WI 5.14 mirrors `update-zskills` via
`mirror-skill.sh` (hook-compatible). WI 5.6 also mirrors
`hooks/block-unsafe-generic.sh` (per-file `cp`, not affected by
the recursive-rm hook).

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
- [ ] `! test -e tests/test-stop-dev.sh` (file deleted per WI 5.12).
- [ ] `! grep -F 'test-stop-dev.sh' tests/run-all.sh` (entry
      removed per WI 5.12).
- [ ] `grep -F 'failing stub by default' hooks/block-unsafe-generic.sh`
      ≥ 2 (one for each updated block-reason; lines 159 and 177).
- [ ] `diff hooks/block-unsafe-generic.sh .claude/hooks/block-unsafe-generic.sh`
      empty (mirror).
- [ ] **Pre-edit gate `{{PORT_SCRIPT}}` zero-hits across
      apply-preset.sh + SKILL.md + CLAUDE_TEMPLATE.md** (regression
      guard — already passes as of refine-round-1).
- [ ] **Pre-edit gate `{{DEV_SERVER_CMD}}` zero-hits in
      apply-preset.sh** (regression guard — already passes; SKILL.md
      placeholder-mapping row at L323 is intentional and excluded
      from this gate per F5).
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
      18-28 (post-WI-5.7 Dev Server section) and confirm:
      no orphan `{{PORT_SCRIPT}}` reference, no orphan
      `{{DEV_SERVER_CMD}}` codeblock outside its placeholder-bound
      use, "to start" / "to stop" pair reads naturally,
      port-section references stub-callout convention.
      Additionally verify the `{{TIMEZONE}}` placeholder at L107
      (in the worktree-rules `.landed` heredoc) is preserved — DA4
      regression guard.
- [ ] 6.3 — **`briefing-extra.sh` decision: DEFERRED.**
      **Rationale:** there is no current consumer demand for a
      briefing-extension seam. The convention is now formalized in
      `references/stub-callouts.md`, the dispatch helper is shipped
      and tested, and adding a future `briefing-extra.sh` callout
      is mechanical — though note `briefing` is currently
      DUAL-RUNTIME: insertion at the end of the output assembly in
      BOTH `briefing.cjs` AND `briefing.py` (cjs preferred / py3
      fallback per `skills/briefing/SKILL.md:18-28`), plus one
      stub file, one test, one Step-D bullet. Likely a single PR
      if the dual-runtime status holds; if `briefing.py` has been
      retired by then, single-runtime suffices. Per
      `feedback_dont_defer_hole_closure.md`: this is NOT a
      deferred hole — there is no current bug or missing contract.
      It is a **deferred extension point** with a clear pattern
      to follow when a real need surfaces.

      Document this decision in `references/stub-callouts.md`
      under a "Future callouts" subsection as a single line so the
      next agent doesn't re-litigate the deferral itself:
      > - `briefing-extra.sh` — declined for now; revisit when
      >   first consumer demand surfaces. Note: `briefing` is
      >   dual-runtime (cjs + py3); a future callout would need to
      >   be wired in both unless the .py runtime has been retired.
- [ ] 6.4 — **`/update-zskills` Step D install report.** The Step
      D install report at `skills/update-zskills/SKILL.md:912`
      reads `Report: "Installed N scripts: [list]"`. The `[list]`
      placeholder is dynamic in the existing implementation (Step D
      iterates over copied filenames). Verify:
      `grep -A20 'Installed N scripts' skills/update-zskills/SKILL.md`
      — confirm the report-line list is dynamic; no edit needed
      if the existing format auto-includes the new bullets. If
      it's hardcoded, extend to include the four new stubs
      (`post-create-worktree.sh`, `dev-port.sh`, `start-dev.sh`,
      plus any other `stubs/` additions). Step D.5 (stale-Tier-1
      migration, SKILL.md:914+) is a separate report and is **not**
      affected by the new stubs (they are not in STALE_LIST).
- [ ] 6.5 — **Mirror** any touched skills (likely just
      `update-zskills` for the references update):
      ```bash
      bash scripts/mirror-skill.sh update-zskills
      ```

### Design & Constraints

**`briefing-extra.sh` deferral is principled, not lazy.** Phase 6.3
is explicit: there is no consumer demand, the seam is mechanical to
add later (in either single- or dual-runtime form), the convention
is now documented. This is the distinction
`feedback_dont_defer_hole_closure.md` draws between "hole closure"
(close it now) and "extension point" (add when needed). Holes need
closing because they're broken contracts; extension points are
speculation.

**Step D install report (F7/DA14).** WI 6.4's anchor is line 912
(the dynamic-`[list]` install report inside Step D). This is
distinct from Step C.9's rename-list reference at L880-882 (which
is about the rename-table preview displayed in Step C step 6, a
different feature entirely). Earlier drafts of this WI conflated
the two; the current text is anchored to L912.

**No hook edits.** Phase 5.6 already concluded `block-unsafe-generic.sh`
help-text edits.

### Acceptance Criteria

- [ ] `grep -nE 'scripts/(test-all|stop-dev|start-dev)' README.md`
      — every match is in stub-aware prose.
- [ ] `grep -F '{{PORT_SCRIPT}}' CLAUDE_TEMPLATE.md` returns no
      matches (regression guard — already passes as of
      refine-round-1; `{{PORT_SCRIPT}}` was removed by the
      prerequisite plan).
- [ ] `[ "$(grep -c -F '{{TIMEZONE}}' CLAUDE_TEMPLATE.md)" -eq 1 ]`
      (DA4 regression guard against accidental duplication or
      removal during WI 5.7's Dev Server edit).
- [ ] `grep -F 'briefing-extra' skills/update-zskills/references/stub-callouts.md`
      matches (decision recorded, including the dual-runtime note).
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

CHANGELOG entry, plan-index update, frontmatter flip; pin the
stub-body versioning policy that prevents Step D.5 false-positives
on future stub revisions (DA6).

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
- [ ] 7.4 — **Pin the stub-body versioning policy (DA6).** Add a
      paragraph to `skills/update-zskills/references/script-ownership.md`
      under a new "Failing-stub body revisions" subsection:
      > Failing-stub bodies (`post-create-worktree.sh`,
      > `dev-port.sh`, `start-dev.sh`, `stop-dev.sh`,
      > `test-all.sh`) are version-shipped artifacts. Future PRs
      > that change a failing-stub body MUST add the OLD body's
      > hash to
      > `skills/update-zskills/references/tier1-shipped-hashes.txt`
      > so consumers running the prior version are not flagged as
      > user-modified by Step D.5 (consumers' `scripts/stop-dev.sh`
      > / `scripts/test-all.sh` would otherwise mismatch the new
      > shipped hash and emit "WARNING: user-modified" prompts at
      > every `/update-zskills` run, even though the file is
      > pristine).

      This applies to the existing `scripts/stop-dev.sh` and
      `scripts/test-all.sh` only after Phase 5 lands their failing-
      stub bodies; the three stubs in `stubs/` are net-new in this
      plan and have no prior shipped body to grandfather.

      If `tier1-shipped-hashes.txt` does not yet exist (it's a
      Step D.5 mechanism from prereq Phase 4), and the existing
      Step D.5 logic does not currently hash-check `stop-dev.sh`/
      `test-all.sh` (verified at SKILL.md:960-962 — they are
      explicitly excluded from STALE_LIST), the policy is
      forward-looking: the doc captures the requirement so that if
      Step D.5 is ever extended to cover failing-stub bodies, the
      OLD-hash discipline is in place.

### Acceptance Criteria

- [ ] `grep -F 'consumer stub-callout convention' CHANGELOG.md`
      matches (loose pin tolerates prefix re-framing).
- [ ] `head -10 plans/CONSUMER_STUB_CALLOUTS_PLAN.md` shows
      `status: complete` and `completed:` lines.
- [ ] `grep -q 'CONSUMER_STUB_CALLOUTS' plans/PLAN_INDEX.md`
      succeeds OR file absent.
- [ ] `grep -F 'Failing-stub body revisions' skills/update-zskills/references/script-ownership.md`
      matches (WI 7.4 stub-body versioning policy recorded).
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1–6.

## Drift Log

Structural comparison of the plan as originally drafted (committed
2026-04-25, single commit `4aa8864`) vs current state after
`/refine-plan` round 1 (post-prerequisite-landing).

The plan has only one prior commit; per `/refine-plan` convention,
the drift log records changes from the plan-as-originally-written to
the post-refine state, plus the **external** codebase drift that
forced this refine pass (the prerequisite plan
`SCRIPTS_INTO_SKILLS_PLAN.md` landed via PRs #94–#100 and PR #88
introduced `scripts/mirror-skill.sh` after this plan was drafted).

### Internal drift — refinements applied to remaining phases

| Phase | Planned | Actual after refine | Delta |
|-------|---------|---------------------|-------|
| 1 — Staleness gate | 4 WIs (frontmatter check, multi-anchor fs check, CHANGELOG check, halt) | 4 WIs (unchanged) + Design note added: "Post-prereq-landing reality: anchors all pass against current main; Phase 1 functions as regression guard, not discovery check" | F13 fix; WI 1.3 grep alternation tightened (DA16) — middle alternation now requires `Tier` keyword |
| 2 — Stub-callout convention + dispatch helper | 5 WIs | 5 WIs + 8th test case (literal `--` argument forwarding, DA10) + canonical-source rule for `stubs/` vs `scripts/` (DA5) + first-run-marker read-only-fs handling (DA9) | F6/DA12 anchor renamed (`fake-consumer-project` → FIX_NN-style); DA15 AC split per-file; lib body marker-write tightened |
| 3 — `post-create-worktree.sh` callout | 5 WIs | 5 WIs (unchanged) | F16 line citations updated (320–341 → 336–355; 326 → 340); F3/DA1 mirror snippet at WI 3.5 → `bash scripts/mirror-skill.sh create-worktree && bash scripts/mirror-skill.sh update-zskills` |
| 4 — `dev-port.sh` callout | 6 WIs | 6 WIs (unchanged) | F1/F2/DA2 verbatim before-block re-anchored to `skills/update-zskills/scripts/port.sh:45-55`; upstream-context marker added for L24-43 runtime config-read; insertion point pinned at L50; Design note line numbers updated 27→43, 12→18; `_ZSK_REPO_ROOT` reframed to "do not redeclare in inserted block"; WI 4.6 mirror via mirror-skill.sh |
| 5 — `start-dev.sh` (new) + stop-dev.sh / test-all.sh conversions | 14 WIs | 14 WIs | F4/DA3 WI 5.7 verbatim before-block re-anchored to `CLAUDE_TEMPLATE.md:18-28`; `{{PORT_SCRIPT}}` reference dropped (placeholder gone); `{{MAIN_REPO_PATH}}` and L28 kill-9 paragraph preserved; F5 pre-edit gate split per token (PORT_SCRIPT all 3 files / DEV_SERVER_CMD apply-preset.sh only — SKILL.md:323 doc row excluded from abort); F8 stop-dev.sh bullet citation 906–908 → 901–903; F9 WI 5.10 rewritten as REPLACE of existing test-all.sh bullet at SKILL.md:904-906; F11/DA7 WI 5.12 + AC L1060 reconciled (delete tests/test-stop-dev.sh entirely; remove from run-all.sh); F10 phrasing standardized on "failing stub by default"; F3/DA1 mirror snippet at WI 5.14 → `bash scripts/mirror-skill.sh update-zskills` |
| 6 — Hooks / CLAUDE_TEMPLATE / docs sweep + briefing-extra.sh | 5 WIs | 5 WIs | F7/DA14 WI 6.4 re-anchored to SKILL.md:912 install report (Step C.9 conflation removed); F12/DA11 WI 6.3 deferral acknowledges briefing dual-runtime (cjs+py3); DA4 `{{TIMEZONE}}` regression-guard AC added (`grep -c -F '{{TIMEZONE}}' CLAUDE_TEMPLATE.md = 1`); F14 WI 5.11(b) reframed as regression guard |
| 7 — Close-out | 3 WIs | 4 WIs (added 7.4) | DA6 new WI 7.4 documents failing-stub-body versioning policy in `references/script-ownership.md` (prevents Step D.5 false-positives on future stub revisions) |

### External drift — codebase changes that forced this refine pass

| Source | What changed | Where it bit the plan |
|--------|--------------|------------------------|
| PR #88 — `scripts/mirror-skill.sh` (hook-compatible mirror helper) | New helper script using per-file `rm` + `find -print0` to avoid `block-unsafe-generic.sh:217-222` (`RM_RECURSIVE` regex). Prereq plan `SCRIPTS_INTO_SKILLS_PLAN.md` adopted this as the canonical mirror recipe across 10+ call-sites. | This plan's WI 2.5, 3.5, 5.14 shipped inline `rm -rf .claude/skills/<name> && cp -a ...` snippets — hard-blocked by the local hook. Refine replaced all three with `bash scripts/mirror-skill.sh <name>`. |
| PRs #94–#100 — `SCRIPTS_INTO_SKILLS_PLAN.md` landing (Tier-1 scripts moved into owning skills) | `scripts/port.sh` → `skills/update-zskills/scripts/port.sh`, rewritten with new runtime config-read block (BASH_REMATCH against `.claude/zskills-config.json`); now 61 lines. `PROJECT_ROOT` from `git rev-parse --show-toplevel` at L18; runtime config-read at L24-43; DEV_PORT block at L45-49; main-repo block at L51-55. `_ZSK_REPO_ROOT` briefly reintroduced at L28 and unset at L43. | WI 4.1's "verbatim before block (`scripts/port.sh:33-43`)" + WI 4.1 Design line citations (`port.sh:27`, `line 12`) all stale. Refine re-anchored to L45-55 with explicit upstream-context marker for L24-43 (do-not-modify). |
| PRs #94–#100 — `CLAUDE_TEMPLATE.md` updates | `{{PORT_SCRIPT}}` placeholder removed entirely; `## Dev Server` heading now at L18 (was L7 region in plan); new `lsof -ti :<port> | xargs kill` paragraph at L28; new `{{TIMEZONE}}` placeholder at L107 (worktree-rules `.landed` heredoc example). | WI 5.7's "verbatim before block (`CLAUDE_TEMPLATE.md:7-15`)" cited the wrong section (L7-15 is Subagent Dispatch); the `{{PORT_SCRIPT}}` quote was already stale (placeholder gone). Refine re-anchored to L18-28, dropped `{{PORT_SCRIPT}}` reference, preserved the new kill-9 paragraph and `{{MAIN_REPO_PATH}}`. Added DA4 regression guard for `{{TIMEZONE}}`. |
| PRs #94–#100 — `update-zskills/SKILL.md` Step D / D.5 reshape | Step D heading at L895; bullets for `stop-dev.sh` (L901-903) AND `test-all.sh` (L904-906); install report `Installed N scripts: [list]` at L912; new Step D.5 (stale-Tier-1 migration) heading at L914; STALE_LIST at L931-947; exclusion comment for `stop-dev.sh`/`test-all.sh`/`build-prod.sh`/`mirror-skill.sh` at L960-962. | Plan's WI 5.5 cite (`906-908`) was off (actual 901-903 — F8). WI 5.10 falsely claimed Step D had "no test-all.sh entry" — bullet IS present at 904-906; refine rewrote as REPLACE not unconditional ADD (F9). WI 6.4 anchored to L880-882 (Step C.9 rename-list territory) instead of L912 install report; refine re-anchored (F7/DA14). DA6 surfaced the failing-stub-body-versioning concern with Step D.5; refine added new WI 7.4. |
| External — `skills/briefing/scripts/` is now dual-runtime | `briefing.cjs` (1929 lines) AND `briefing.py` (1710 lines); `skills/briefing/SKILL.md:18-28` prefers cjs / falls back to py3. | WI 6.3's deferred-`briefing-extra.sh` rationale referenced only `briefing.cjs`. Refine acknowledged dual-runtime in the deferral note (F12/DA11). |
| External — `tests/test-create-worktree.sh` fixture pattern | The phrase "fake-consumer-project" never existed; the actual fixture pattern at L815-836 is FIX_NN-style temp-fixture (`FIX_22="/tmp/cw-c22-fixture-$$"` + `git init -b main` + `cp` skill scripts + `chmod +x`). | WI 2.3 / WI 3.4 cited the pattern by the misleading descriptor "fake-consumer-project". Refine reworded both to name the FIX_NN pattern explicitly (F6/DA12). |
| External — `apply-preset.sh` content | Zero matches today for `PORT_SCRIPT`, `DEV_SERVER_CMD`, `TIMEZONE`, `test-all`, `stop-dev`, `start-dev`. | WI 5.7's pre-edit gate over-broadly matched `SKILL.md:323` (placeholder-mapping documentation row); refine split the gate per token. WI 5.11(b) gate already passes; refine reframed as a regression guard (F5/F14/DA8). |

## Plan Review

**Refinement process:** `/refine-plan` with 1 round of adversarial
review (rounds budget = 2 per user invocation; converged in 1).

**Convergence:** Converged at round 1 — orchestrator's judgment.

The consolidated disposition table below (`### Round 3 finding
dispositions`) records all 32 findings (16 reviewer F1–F16 + 16
devil's-advocate DA1–DA16) with per-finding evidence and a
`Verified, fixed` outcome on every entry. Zero `Justified — evidence
did not reproduce` entries; zero `Justified — claim not verifiable`
entries; zero deferrals. Per the
convergence rule "0 substantive issues → converged → next phase",
the orchestrator short-circuited round 2 (substantive remaining
issues = 0). Independent spot-checks against current main confirmed
the critical fixes:

- `port.sh` line citations (L18 / L24-43 / L43 / L45-49 / L51-55)
  match reality (`Read skills/update-zskills/scripts/port.sh`).
- `CLAUDE_TEMPLATE.md:18-28` verbatim before-block matches reality
  (Dev Server heading at L18, `{{DEV_SERVER_CMD}}` at L21+L26,
  L28 kill-9 paragraph, `{{MAIN_REPO_PATH}}` at L24).
- `bash scripts/mirror-skill.sh <name>` adopted at WI 2.5, 3.5, 4.6,
  5.14, 6.5 (no remaining inline `rm -rf .claude/skills/<name>`
  blocked snippets in the plan).
- WI 5.7 pre-edit gate split per token; SKILL.md:323 documentation
  row no longer trips abort.
- WI 5.10 re-framed as REPLACE of existing test-all.sh bullet at
  L904-906 (not unconditional ADD).
- New WI 7.4 documents failing-stub-body versioning policy.

**Remaining concerns:** None blocking. Two judgment-class items
worth noting for the implementing agent:

1. **WI 5.12 deletes the existing `tests/test-stop-dev.sh` (7
   behavioral cases) entirely.** The rationale (zskills doesn't test
   consumer code; once stop-dev.sh is a failing-stub the consumer
   customizes, the 7 cases don't apply to anyone's runtime) is
   sound, and the disposition rejects the alternative
   "single-case test that the stub exits 1" as not adding signal
   beyond the AC `grep -F 'not configured' scripts/stop-dev.sh`. The
   7 cases remain in git history if a future consumer wants them as
   a starting point. If a reviewer prefers retaining a single-case
   test, that's a one-WI delta.
2. **WI 7.4's failing-stub-body versioning policy is forward-
   looking.** Step D.5 today excludes stop-dev.sh/test-all.sh from
   STALE_LIST (per SKILL.md:960-962), so the "user-modified"
   false-positive DA6 raised does not bite immediately. The policy
   captures the requirement so a future Step D.5 extension that
   covers failing-stub bodies will inherit the OLD-hash discipline.

### Round 3 finding dispositions

| ID | Severity | Disposition | Evidence | Fix summary |
|----|----------|-------------|----------|-------------|
| F1 | critical | Verified, fixed | Read port.sh fresh: PROJECT_ROOT L18, config block L24-43, unset L43, DEV_PORT L45-49, MAIN_REPO L51-55 (file is 61 newline-terminated lines plus a no-NL final line, total 62 logical lines) | WI 4.1 verbatim before-block re-anchored to `skills/update-zskills/scripts/port.sh:45-55`; added "[lines 24-43: runtime config-read for MAIN_REPO and DEFAULT_PORT — do not modify]" context marker; insertion point pinned at L50 |
| F2 | major | Verified, fixed | port.sh:18 `PROJECT_ROOT=$(git rev-parse...)` (line 12 is comment); port.sh:43 `unset _ZSK_REPO_ROOT _ZSK_CFG`; `_ZSK_REPO_ROOT` is set inside config-read at L28 then unset at L43 | WI 4.1 Design line numbers updated 27→43, 12→18; reframed "Do not re-introduce" to "do not redeclare `_ZSK_REPO_ROOT` inside the inserted callout block — port.sh L28+L43 already creates and unsets it inside the upstream runtime config-read block" |
| F3 | critical | Verified, fixed | hooks/block-unsafe-generic.sh:201 (is_safe_destruct requires literal `/tmp/`); :217 (RM_RECURSIVE regex); scripts/mirror-skill.sh exists (74 lines, hook-compatible per-file rm); 33 hits of `mirror-skill` in SCRIPTS_INTO_SKILLS_PLAN.md, 0 in CONSUMER_STUB_CALLOUTS_PLAN.md | WI 2.5, 3.5, 5.14 inline `rm -rf .claude/skills/<name>` snippets replaced with `bash scripts/mirror-skill.sh <name>`; per-phase Design note added: "Inline `rm -rf .claude/skills/<name>` is blocked by `block-unsafe-generic.sh:217-222`; `mirror-skill.sh` (PR #88) avoids the gate via per-file `rm` and `find -print0`." |
| F4 | critical | Verified, fixed | CLAUDE_TEMPLATE.md is 188 lines; `## Dev Server` heading at L18; `{{DEV_SERVER_CMD}}` at L21 (codeblock) and L26 (prose); `{{PORT_SCRIPT}}` zero hits in any file; kill-9 paragraph at L28; `{{TIMEZONE}}` at L107; `{{MAIN_REPO_PATH}}` at L24 | WI 5.7 verbatim before-block re-anchored to L18-28; quoted current Dev Server prose verbatim including the kill-9 paragraph at L28; dropped `{{PORT_SCRIPT}}` reference; preserved `{{MAIN_REPO_PATH}}`; corrected the trailing "drop the codeblock at lines 9-11" prose |
| F5 | critical | Verified, fixed | grep -nE on `{{PORT_SCRIPT}}\|{{DEV_SERVER_CMD}}` returns 1 hit at SKILL.md:323 (placeholder-mapping doc table row); apply-preset.sh and CLAUDE_TEMPLATE.md zero hits | WI 5.7 pre-edit gate split: `{{PORT_SCRIPT}}` checked across apply-preset.sh + SKILL.md + CLAUDE_TEMPLATE.md (zero hits required); `{{DEV_SERVER_CMD}}` checked only in apply-preset.sh (zero hits required); SKILL.md row at L323 is legitimate documentation, must not trigger abort |
| F6 | major | Verified, fixed | `grep -i 'fake-consumer\|fake_consumer\|setup_fake' tests/test-create-worktree.sh` → 0 hits; FIX_22 fixture at L828-836 confirmed | WI 2.3 and WI 3.4 reworded to name the FIX_NN pattern explicitly (cite tests/test-create-worktree.sh:828-836 with the FIX_NN structure quoted) |
| F7 | major | Verified, fixed | SKILL.md L880-882 is Step C.9 closing prose (rename-list); Step D heading L895; Step D body 897-906; install report L912; Step D.5 L914 | WI 6.4 re-anchored to SKILL.md:912 (`Report: "Installed N scripts: [list]"`); dropped the "lines 880-882 reference rename-list" sentence; clarified Step D.5 is a separate report unaffected by the new stubs |
| F8 | minor | Verified, fixed | Step D `stop-dev.sh` bullet at SKILL.md:901-903 (not 906-908); test-all.sh bullet at 904-906 | WI 5.5 line citation updated 906-908 → 901-903 |
| F9 | major | Verified, fixed | SKILL.md Step D today HAS both a stop-dev.sh bullet (901-903) AND a test-all.sh bullet (904-906); plan claim of "no test-all.sh entry" is wrong | WI 5.10 rewritten as REPLACE of the existing test-all.sh bullet at 904-906 with the failing-stub-aware bullet; "Verified" prose corrected (removed false `clear-tracking.sh`/`apply-preset.sh` bullet claim) |
| F10 | minor | Verified, fixed | Plan WI 5.6 says "failing stub by default"; Phase 5 Design L1030 said "consumer-customizable stub"; AC L1062 says "failing stub by default" | Phase 5 Design L1030 prose changed to "failing stub by default" to match WI 5.6 verbatim and the AC; standardized phrasing across the phase |
| F11 | minor | Verified, fixed | WI 5.12 says "single-case test"; AC L1060 said "reference impl + stub-fail case"; WI 5.3 explicitly drops `references/stop-dev-reference.sh` | AC L1060 reconciled with WI 5.12 (see DA7 for the broader 7-test deletion concern) |
| F12 | minor | Verified, fixed | `ls skills/briefing/scripts/` shows briefing.cjs AND briefing.py; SKILL.md L18-28 (preferred + fallback prose) | WI 6.3 deferral rationale updated to acknowledge dual-runtime: "insertion at the end of the output assembly in BOTH briefing.cjs and briefing.py (cjs preferred / py3 fallback per skills/briefing/SKILL.md:18-28)" |
| F13 | minor | Verified, fixed | All 8 anchors of WI 1.2 pass on current main | Phase 1 Design augmented with one-line note: "Post-prerequisite-landing reality: as of refine-round-1, all 1.1-1.3 anchors pass against current main; Phase 1 functions as a regression guard, not a discovery check." |
| F14 | minor | Verified, fixed | `grep -F 'scripts/test-all.sh' apply-preset.sh` → 0 hits today; the gate is now a regression guard | WI 5.11(b) prose reframed as a regression guard ("passes as of refine-round-1; if a future apply-preset.sh edit reintroduces `bash scripts/test-all.sh` as a default `testing.full_cmd`, this gate flags the regression") |
| F15 | major | Verified, fixed | Round History L1204 declared "Converged" pre-prereq-landing; per `feedback_convergence_orchestrator_judgment.md` convergence is the orchestrator's call | Round History updated: row 2's "Converged" qualified as "Converged in round 2 against pre-prereq main; re-opened in round 3 (refine-plan post-prereq) for SCRIPTS_INTO_SKILLS_PLAN landing drift"; new Round 3 row appended; Plan Quality augmented with refine-round-1-post-prereq paragraph |
| F16 | minor | Verified, fixed | create-worktree.sh tail block: WI 1a.11 .zskills-tracked rollback at L336-342 (exit 8 at L340); .worktreepurpose write at L344-350 (exit 8 at L347); WI 1a.12 final printf at L354 | WI 3.1 Design citation updated `(lines 320-341)` → `(lines 336-355)` and `(line 326)` → `(line 340)`; ellipsis-meaning note added |
| DA1 | critical | Verified, fixed (joint with F3) | hooks/block-unsafe-generic.sh:201,217 + plan WI 2.5 L331, WI 3.5 L558+L560, WI 5.14 L1000-1001 | See F3 fix. Plan Quality footnote added: "mirror-skill.sh (PR #88) is the canonical hook-compatible mirror recipe used throughout SCRIPTS_INTO_SKILLS_PLAN; this plan adopts the same convention" |
| DA2 | major | Verified, fixed (joint with F1+F2) | port.sh full read; line numbers as in F1/F2 | See F1 + F2 fixes. Design note clarified: the new runtime-config-read block at L24-43 must NOT be edited by WI 4.1; the only edit lands between L49 and L51 |
| DA3 | critical | Verified, fixed (joint with F4) | CLAUDE_TEMPLATE.md L18 (## Dev Server), L21 (`{{DEV_SERVER_CMD}}` codeblock), L24 (port prose with `{{MAIN_REPO_PATH}}`), L26 (`{{DEV_SERVER_CMD}}` prose), L28 (kill-9 paragraph) | See F4 fix. After-block updated to preserve the kill-9 paragraph at L28 verbatim and keep `{{MAIN_REPO_PATH}}` reference for apply-preset.sh substitution |
| DA4 | minor | Verified, fixed | `{{TIMEZONE}}` exists at CLAUDE_TEMPLATE.md:107 only; not mentioned in plan | WI 6.2 AC added: `grep -F '{{TIMEZONE}}' CLAUDE_TEMPLATE.md` returns exactly 1 (regression guard against accidental duplication or removal); Phase 5 Design footnote added that WI 5.7 edits MUST NOT touch the worktree-rules `.landed` heredoc section (L96-114) |
| DA5 | major | Verified, fixed | WI 2.4 establishes new `stubs/` dir; WI 5.4/5.9 keep stop-dev.sh/test-all.sh at `scripts/`; SKILL.md:960 explicitly excludes them from STALE_LIST | Phase 2 Design augmented with explicit canonical-source rule: `stubs/` holds NEW failing-stub source templates; `scripts/` holds the prereq's existing stop-dev.sh and test-all.sh which Phase 5 OVERWRITES in place. Step D never reads from both for the same name. |
| DA6 | major | Verified, fixed | SKILL.md:931-947 STALE_LIST; SKILL.md:960-962 exclusion comment | New WI 7.4 documents the failing-stub-body-versioning contract in `references/script-ownership.md`; Plan Quality footnote added |
| DA7 | major | Verified, fixed (joint with F11) | tests/test-stop-dev.sh has 7 currently-passing behavioral tests; plan WI 5.3 drops reference impl; AC L1060 contradicts WI 5.12 | WI 5.12 rewritten: delete tests/test-stop-dev.sh entirely (zskills doesn't test consumer code); removed test-stop-dev.sh from tests/run-all.sh; AC L1060 dropped. The 7 behavioral tests are preserved in git history if any consumer wants to copy them as a starting point. |
| DA8 | minor | Verified, fixed (joint with F13+F14) | grep -F '{{PORT_SCRIPT}}' CLAUDE_TEMPLATE.md → 0 today; grep -F 'scripts/test-all.sh' apply-preset.sh → 0 today | Reframing per F13/F14: each already-passing AC explicitly labeled "regression guard" |
| DA9 | minor | Verified, fixed | Plan WI 2.2 L278-282 lib body | Lib marker-write logic tightened: `if mkdir -p "$notes_dir" 2>/dev/null && touch "$marker" 2>/dev/null; then echo ... ; fi` — note suppressed when marker write fails (read-only fs case); behavior pinned in Phase 2 Design |
| DA10 | minor | Verified, fixed | Plan WI 2.2 L264 `[ "$1" = "--" ] && shift` | Phase 2 Design notes `--` discriminator is REQUIRED at every callsite; test case 8 added to WI 2.3 ("stub gets literal `--` argument in `$@`" — verifies dispatcher only consumes the FIRST `--`, forwards subsequent verbatim) |
| DA11 | minor | Verified, fixed (joint with F12) | See F12 evidence | See F12 fix |
| DA12 | minor | Verified, fixed (joint with F6) | See F6 evidence | See F6 fix |
| DA13 | major | Verified, fixed (joint with F15) | See F15 evidence | See F15 fix; explicit Drift Log section added per /refine-plan convention |
| DA14 | minor | Verified, fixed (joint with F7) | See F7 evidence | See F7 fix |
| DA15 | minor | Verified, fixed | Plan WI 2.5 AC L420-425 with `≥ 2 matches` ambiguity | AC split into two per-file checks: `grep -c -F 'stub-lib missing' skills/create-worktree/scripts/create-worktree.sh` ≥ 1 AND `grep -c -F 'stub-lib missing' skills/update-zskills/scripts/port.sh` ≥ 1 |
| DA16 | minor | Verified, fixed | Plan WI 1.3 grep alternation | WI 1.3 alternation tightened: middle alternation now requires "Tier" keyword (`move.*Tier.?1.*into.*skills`) not just "scripts"; passes today against current CHANGELOG.md L6 |

### Round History

| Round | Reviewer Findings | Devil's Advocate Findings | Substantive | Resolved |
|-------|-------------------|---------------------------|-------------|----------|
| 1 (pre-prereq, /draft-plan)     | 16                | 18                        | 34           | 34/34 |
| 2 (pre-prereq, /draft-plan)     | 6                 | combined                  | 6            | 6/6 — declared "Converged" pre-prereq |
| 3 (post-prereq, /refine-plan)   | 16                | 16                        | 32 (de-dup'd; ~26 unique) | 32/32 — orchestrator-confirmed Converged |

The pre-prereq "Converged at round 2" badge has been re-evaluated by
this refine pass: post-prerequisite-landing drift (PR #88 +
PRs #94–#100) invalidated multiple plan anchors (verbatim before-
blocks for `port.sh` and `CLAUDE_TEMPLATE.md`, Step D line cites,
mirror-snippet hook-block compatibility) — the convergence claim was
correct AS OF its timestamp but became stale when the prerequisite
landed. The current convergence is grounded in current main as of
2026-04-28.

#### Round 3 (refine-plan, post-prereq) disposition summary

All 32 findings `Verified, fixed`. Critical (4): F1/DA2 port.sh
verbatim re-anchor; F3/DA1 mirror-skill.sh adoption; F4/DA3
CLAUDE_TEMPLATE.md verbatim re-anchor; F5 pre-edit gate per-token
split. Major (8): F2 port.sh Design line numbers; F6/DA12 FIX_NN
fixture rename; F7/DA14 Step D install report re-anchor; F9 WI 5.10
REPLACE-not-ADD; F15/DA13 Round History updated; DA5 stubs/+scripts/
canonical-source rule; DA6 stub-body versioning policy (new WI 7.4);
DA7 WI 5.12 / AC reconciliation. Minor (15+): F8/F10/F11/F12/F13/F14/F16
+ DA4/DA8/DA9/DA10/DA11/DA15/DA16. See per-phase disposition tables
in the refined output for evidence anchors.
