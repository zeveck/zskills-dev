---
title: Canary Failure Injection
created: 2026-04-16
status: active
---

# Plan: Canary Failure Injection

> **Landing mode: PR** — All phases land as separate PRs.

## Overview

Build `tests/test-canary-failures.sh` — a regression suite that locks in
the hardened zskills pipeline's loud-failure behavior under adversarial
inputs. External users clone zskills, run `bash tests/run-all.sh`, and
see evidence the install catches silent-failure modes on their
machine. This is the shareability gate.

**Scope (strict):** lock in CURRENT behavior as executable regression
tests. No bug fixes. No design changes. If a reproducer surprises you
by catching unwanted behavior, file a follow-up issue — do NOT mix a
fix into the same phase.

**Deliverable:**

- `tests/test-canary-failures.sh` (new, executable).
- `tests/fixtures/canary/` directory for any non-trivial fixture files.
- `tests/run-all.sh` extended with one `run_suite` line.

**Note on the in-progress sentinel (yellow-circle emoji):** the current
`scripts/post-run-invariants.sh` invariant #6 is a whole-file `grep -q`
for that character. This plan therefore uses the character ONLY in the
Progress Tracker table rows (where its presence is transient during
phase execution). Prose, fixtures, and examples below use phrases like
"the in-progress sentinel" or "yellow-circle emoji" instead, so the
plan's own invariant-#6 check doesn't false-positive on itself at EOP.

## Preflight

Before starting:

- `gh auth status` succeeds.
- Repo settings: auto-merge enabled, squash-merge allowed, branch
  protection permits auto-merge (not requiring up-to-date branch).
- `/tmp` has room for one worktree at a time (each phase's worktree
  is cleaned up after its PR merges before the next phase starts).
- `bash tests/run-all.sh` passes on current main (baseline).

**Launch — sequential per-phase PRs (intentional, not `finish auto pr`):**

```
/run-plan plans/CANARY_FAILURE_INJECTION.md 1 auto pr
# wait for PR to merge, then:
git pull --ff-only origin main
/run-plan plans/CANARY_FAILURE_INJECTION.md 2 auto pr
# ... repeat for phases 3, 4, 5
```

**Why per-phase PR (atypical for plans, deliberate here):** most plans
should be landing-mode-agnostic — the user picks `finish auto pr` for
one PR or `<N> auto pr` for many. This canary prescribes sequential
per-phase PRs because (a) each phase's test additions are small (~50-150
lines) and independently reviewable; (b) a bug in one phase's
reproducer doesn't block landing the others; (c) the per-phase PR
exercises the hardened PR-mode pipeline 5× rather than 1×, providing
incidental smoke-test value alongside the regression suite itself.

After each phase's PR merges, the skill's `land-phase.sh` cleans up the
worktree + local branch + remote branch. The next invocation creates a
fresh worktree on a fresh branch (same name) from the updated `main`,
which now includes the previous phase's changes.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1 — Scaffold + block-unsafe-generic.sh stash | ✅ Done | `cace895` | 18 tests (6+7+5) |
| 2 — land-phase.sh | ⬚ | | |
| 3 — post-run-invariants.sh | ⬚ | | |
| 4 — block-agents.sh | ⬚ | | |
| 5 — /commit reviewer + Phase 7 | ⬚ | | |

## Shared conventions (all phases)

### Test suite scaffold (created by Phase 1)

Phase 1 writes `tests/test-canary-failures.sh` with this exact structure
(no inline fixture data — fixtures live in `tests/fixtures/canary/`):

```bash
#!/bin/bash
# tests/test-canary-failures.sh — regression suite for silent-failure catches.
#
# Each section asserts loud-failure behavior for one enforcing layer
# (hook / script / skill prompt). Run standalone or via tests/run-all.sh.

set -u

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
FIXTURES="$REPO_ROOT/tests/fixtures/canary"
PASS_COUNT=0
FAIL_COUNT=0
FIXTURE_DIRS=()

cleanup_fixtures() {
  if [ "${#FIXTURE_DIRS[@]}" -eq 0 ]; then return; fi
  local d
  for d in "${FIXTURE_DIRS[@]}"; do
    [ -n "$d" ] && [ -d "$d" ] && chmod -R u+w "$d" 2>/dev/null
    [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
  done
}
trap cleanup_fixtures EXIT

pass() { printf '\033[32m  PASS\033[0m %s\n' "$1"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { printf '\033[31m  FAIL\033[0m %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT+1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Hook helper: construct JSON on stdin, assert deny + substring
expect_deny_substring() {
  local label="$1" cmd="$2" want="$3" hook="$4"
  local json result
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  result=$(printf '%s' "$json" | bash "$hook" 2>/dev/null) || true
  if [[ "$result" == *'"permissionDecision":"deny"'* && "$result" == *"$want"* ]]; then
    pass "$label"
  else
    fail "$label — want deny with '$want', got: $result"
  fi
}

expect_allow() {
  local label="$1" cmd="$2" hook="$3"
  local json result
  json=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$cmd" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')")
  result=$(printf '%s' "$json" | bash "$hook" 2>/dev/null) || true
  if [[ -z "$result" ]]; then
    pass "$label"
  else
    fail "$label — expected empty stdout, got: $result"
  fi
}

# Script helper: run a command, assert rc + stderr substring
expect_script_exit() {
  local label="$1" want_rc="$2" want_stderr="$3"
  shift 3
  local out rc
  out=$("$@" 2>&1) || rc=$?
  rc=${rc:-0}
  if [ "$rc" -eq "$want_rc" ] && [[ "$out" == *"$want_stderr"* ]]; then
    pass "$label"
  else
    fail "$label — rc=$rc want=$want_rc; '$want_stderr' substring? $out"
  fi
}

# Fixture helper: throwaway git repo, auto-cleanup
setup_fixture_repo() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  git -C "$tmp" init -q
  git -C "$tmp" config user.email "canary@test.local"
  git -C "$tmp" config user.name "canary"
  git -C "$tmp" commit --allow-empty -q -m "init"
  echo "$tmp"
}

setup_bare_origin() {
  local tmp
  tmp=$(mktemp -d)
  FIXTURE_DIRS+=("$tmp")
  git init -q --bare "$tmp"
  echo "$tmp"
}

mkdir -p "$FIXTURES"

# --- test sections appended by each phase ---

# (Phase 1 adds: stash)
# (Phase 2 adds: land-phase)
# (Phase 3 adds: invariants)
# (Phase 4 adds: block-agents)
# (Phase 5 adds: commit-reviewer)

echo
echo "Canary failure-injection: $PASS_COUNT passed, $FAIL_COUNT failed"
exit $((FAIL_COUNT > 0))
```

Rationale for choices:

- `set -u` catches undefined-variable bugs. `set -e` is NOT used — rc
  capture (`|| rc=$?`) is explicit.
- Python for JSON escaping: `printf '%q'` isn't JSON-safe; hand-escaping
  is error-prone. Python is already a build dependency (see
  `scripts/briefing.py`).
- Trap-based cleanup: fixtures leak under SIGINT or test-body crashes
  without a trap.
- Fixture-array loop is guarded by `${#FIXTURE_DIRS[@]} -eq 0` to avoid
  unset-array issues under `set -u`.

### tests/run-all.sh integration

Phase 1 adds ONE line at the end of the existing `run_suite` block in
`tests/run-all.sh` (after `run_suite "test-scope-halt.sh"`, which is
currently the last entry after the RESTORE Phase-F additions):

```bash
run_suite "test-canary-failures.sh" "tests/test-canary-failures.sh"
```

The aggregator already sums pass/fail counts and propagates non-zero exit.

### Fixtures directory layout

`tests/fixtures/canary/` holds any fixture file larger than a one-liner:
transcript JSONLs, config JSON, small plan files. Each phase adds what
it needs. No fixture content inside this plan file or inside the test
script.

### Constraints (from CLAUDE.md, binding all phases)

- No `|| true` on fallible operations; explicit `if` for rc branching.
- No `2>/dev/null` on operations whose success matters.
- Capture test output via the `TEST_OUT` idiom — route to
  `/tmp/zskills-tests/$(basename "$(pwd)")/.test-results.txt` so the
  capture file never shows up in `git status` (CLAUDE.md has the
  canonical form). Inspectable-file capture is still the discipline;
  only the location moved out of the working tree. Never pipe through
  `tail`/`head`/`grep`.
- No `git stash` in reproducer scripts (the hook would block it anyway).
- Don't weaken tests to make them pass.
- Real subprocess invocation — no `eval` shortcuts.
- Fixture data in separate files under `tests/fixtures/canary/`.
- The in-progress sentinel character appears ONLY in the Progress
  Tracker table rows of this plan.

---

## Phase 1 — Scaffold + block-unsafe-generic.sh stash reproducers

### Goal

Create the test suite scaffold, wire into `tests/run-all.sh`, and add
reproducers for the stash lockdown: writes deny, reads allow, overmatch
prevention.

### Work Items

- [ ] Create `tests/test-canary-failures.sh` with the scaffold from the
      Shared conventions section. Make executable (`chmod +x`).
- [ ] Create `tests/fixtures/canary/` directory (initially empty — add
      a `.gitkeep` so the directory is tracked).
- [ ] Add `run_suite "test-canary-failures.sh" "tests/test-canary-failures.sh"`
      to `tests/run-all.sh` at the end of the existing `run_suite` block
      (after `run_suite "test-scope-halt.sh"` — the current last entry).
- [ ] Append `section "Stash writes denied (6 cases)"` with 6 tests:

  | Command | Expected deny substring |
  |---------|------------------------|
  | `git stash` | `BLOCKED: git-stash write subcommand forbidden` |
  | `git stash -u` | same |
  | `git stash save "msg"` | same |
  | `git stash push -m "msg"` | same |
  | `git stash drop` | `BLOCKED: git stash drop/clear destroys stashed work permanently` |
  | `git stash clear` | same drop/clear substring |

- [ ] Append `section "Stash reads allowed (7 cases)"` with 7 tests — each
      must produce empty stdout:
      `git stash apply`, `git stash list`, `git stash show`,
      `git stash pop`, `git stash create`, `git stash store abc123`,
      `git stash branch foo`.

- [ ] Append `section "Stash overmatch prevention (5 cases)"` with 5
      tests — each must produce empty stdout:

  | Command |
  |---------|
  | `git commit -m "refactor: remove old git stash logic"` |
  | `echo "git stash push"` |
  | `grep "git stash" somefile.txt` |
  | `printf 'git stash save\n'` |
  | `cat <<EOF` \| `git stash -u` \| `EOF` (multiline heredoc as one command) |

### Design & Constraints

- HOOK path: `$REPO_ROOT/hooks/block-unsafe-generic.sh` (canonical
  source; `.claude/hooks/` is a synced copy — do not test that one).
- The `expect_deny_substring` / `expect_allow` helpers handle all JSON
  escaping via Python. Tests pass the raw command string.
- Phase 1 does NOT touch scripts, hooks, or skills — purely additive.

### Acceptance Criteria

- [ ] `tests/test-canary-failures.sh` exists and is executable.
- [ ] `tests/fixtures/canary/` directory exists with `.gitkeep`.
- [ ] `tests/run-all.sh` diff shows exactly one new `run_suite` line.
- [ ] `bash tests/test-canary-failures.sh` reports `18 passed, 0 failed`.
- [ ] `bash tests/run-all.sh` exits 0 and the suite appears in its output.

### Dependencies

None — first phase.

---

## Phase 2 — land-phase.sh reproducers

### Goal

Lock in `scripts/land-phase.sh`'s loud-failure paths: dirty worktree
refusal, tracked-ephemeral rejection, and ls-remote exit-code
discrimination (0 / 2 / 128).

### Work Items

- [ ] Append `section "land-phase.sh: dirty worktree refused (1 case)"`:
  - Fixture: `setup_fixture_repo`; `git worktree add <path> -b canary/test main`;
    create `.landed` in worktree with a single line `status: landed`;
    add untracked file in worktree (`echo "dirty" > <path>/untracked.txt`).
  - Invoke: `bash scripts/land-phase.sh <path>`.
  - Assert: rc=1, output contains
    `ERROR: Worktree <path> is not clean — cannot safely remove.`

- [ ] Append `section "land-phase.sh: tracked ephemeral rejected (4 cases)"`:
  - Known ephemeral list (matches `EPHEMERAL_FILES` at
    `scripts/land-phase.sh:61`): `.test-results.txt`,
    `.test-baseline.txt`, `.worktreepurpose`, `.zskills-tracked`.
  - For each name: fixture creates repo + feature branch + worktree,
    commits a file with that name into the feature branch, writes
    `.landed` with `status: landed`.
  - Invoke: `bash scripts/land-phase.sh <path>`.
  - Assert: rc=1, output contains
    `ERROR: <filename> is git-tracked in <path> but should be untracked.`
  - **Array-drift guard:** before running any case, grep
    `scripts/land-phase.sh:61` for the `EPHEMERAL_FILES=(...)` line and
    confirm the four names match this plan's list. If not, `fail` with
    an array-drift message so a test author updates the plan rather
    than tests silently passing against a changed list.

- [ ] Append `section "land-phase.sh: ls-remote exit code handling (3 cases)"`:
  - **Case A (origin has branch, rc=0):** fixture creates primary repo
    + bare origin (`setup_bare_origin`); push main; create feature
    branch; push feature branch to origin; set up worktree + `.landed`
    with `status: landed`. Invoke script. Assert rc=0, output contains
    `Worktree removed:`.
  - **Case B (origin does NOT have branch, rc=2):** same fixture but
    skip the feature-branch push. Invoke script. Assert rc=0, output
    contains `Remote branch <branch> already absent — skipping delete.`
  - **Case C (origin unreachable, rc=128):** fixture same as A but
    after setup, overwrite origin URL:
    `git -C <primary> remote set-url origin file:///nonexistent/bare-repo-canary`
    (path must NOT exist). Invoke script. Assert rc=1, output contains
    `ERROR: git ls-remote for <branch> failed with exit 128 — origin unreachable, misconfigured, or auth failure`.

- [ ] Append `section "land-phase.sh: /tmp test-output dir cleanup (1 case)"`:
  - Rationale: commit `66d9138` (EPHEMERAL_TO_TMP Phase 3) extended
    `land-phase.sh` to remove `/tmp/zskills-tests/<basename-of-worktree>/`
    on successful landing (lines 80-88 of the script). Lock in this
    behavior so a future edit can't silently regress it.
  - Fixture: set up repo + worktree + `.landed` with `status: landed`
    (same as the happy-path `ls-remote` fixture from Case A). Before
    invoking, `mkdir -p /tmp/zskills-tests/$(basename "$WORKTREE")`
    and `touch` a sentinel file inside it (e.g., `.canary-sentinel`).
  - Invoke: `bash scripts/land-phase.sh <worktree>`.
  - Assert: rc=0 AND `/tmp/zskills-tests/$(basename "$WORKTREE")` no
    longer exists (directory and sentinel file both gone).
  - Note: `tests/test-hooks.sh:946` already has a compound assertion
    for this behavior; the canary adds a focused single-purpose test
    at the layer-level gate where external users look first.

### Design & Constraints

- Script signature: `bash scripts/land-phase.sh <worktree-path>` — ONE
  argument (verified at `scripts/land-phase.sh:8`). Tests pass exactly
  one arg.
- `.landed` marker format: plain text file starting with `status: landed`
  line (script greps at `:32`, `:133`, `:159`).
- MAIN_ROOT resolution: the script calls `git rev-parse --git-common-dir`,
  so when invoking, tests `cd` into the primary repo first (or use
  `(cd <primary> && bash <abs-path> ...)`).
- Case A / B / C use `setup_bare_origin` to get an isolated origin.
  Case C points origin URL at a non-existent filesystem path to
  reliably produce ls-remote rc=128.

### Acceptance Criteria

- [ ] Section "dirty worktree" passes 1 test.
- [ ] Section "tracked ephemeral" passes 4 tests (one per filename) AND
      the array-drift guard passes.
- [ ] Section "ls-remote" passes 3 tests (cases A, B, C).
- [ ] Section "/tmp test-output dir cleanup" passes 1 test.
- [ ] Cumulative canary suite: 27 tests passing (18 + 9).
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (scaffold + run-all wiring).

---

## Phase 3 — post-run-invariants.sh reproducers

### Goal

Lock in all 7 invariants in `scripts/post-run-invariants.sh` with
correct FAIL-vs-WARN semantics. Invariant #7 is a WARN (exit 0); the
other six are FAILs (exit 1 when fired).

### Work Items

- [ ] Append `section "Invariant #1: worktree on disk (1 case)"`:
  - Fixture: create a directory at `<path>` (a plain `mkdir -p`; no
    git state needed for this invariant).
  - Invoke: `bash scripts/post-run-invariants.sh --worktree <path> --branch "" --landed-status "" --plan-slug "" --plan-file ""`
    from within any git repo.
  - Assert: rc=1, stderr contains
    `INVARIANT-FAIL (#1): worktree still on disk at <path>`.

- [ ] Append `section "Invariant #2: worktree in registry (1 case)"`:
  - Fixture: `setup_fixture_repo`; `git -C <repo> worktree add <wtpath> -b canary/test main`;
    `rm -rf <wtpath>` (removes directory but leaves registry entry).
  - Invoke from `<repo>`: `--worktree <wtpath> --branch "" --landed-status "" --plan-slug "" --plan-file ""`.
  - Assert: rc=1, stderr contains
    `INVARIANT-FAIL (#2): <wtpath> still in git worktree registry`.

- [ ] Append `section "Invariant #3: local branch after landed (2 cases)"`:
  - **Fire case:** fixture creates branch `canary/test-3`; invoke with
    `--branch canary/test-3 --landed-status landed` (other flags empty).
    Assert rc=1, stderr contains
    `INVARIANT-FAIL (#3): local branch canary/test-3 still exists after landed`.
  - **Negative case:** same fixture; invoke with `--landed-status pr-ready`.
    Assert rc=0 and stderr does NOT contain `INVARIANT-FAIL (#3):`.
    (pr-ready intentionally keeps the branch.)

- [ ] Append `section "Invariant #4: remote branch after landed (2 cases)"`:
  - **Fire case:** fixture with bare origin, push `canary/test-4` to
    origin; invoke from primary with `--branch canary/test-4 --landed-status landed`.
    Assert rc=1, stderr contains
    `INVARIANT-FAIL (#4): remote branch origin/canary/test-4 still exists after landed`.
  - **Negative case:** same fixture; invoke with `--landed-status pr-ready`.
    Assert rc=0, no `INVARIANT-FAIL (#4):` in stderr.

- [ ] Append `section "Invariant #5: plan report missing (2 cases)"`:
  - Invoke from a fresh fixture repo (no `reports/` dir).
  - **Fire case:** `--plan-slug canary-5`. Assert rc=1, stderr contains
    `INVARIANT-FAIL (#5): plan report missing at`.
  - **Negative case:** `mkdir -p <primary>/reports` and
    `touch <primary>/reports/plan-canary-5.md`. Assert rc=0.

- [ ] Append `section "Invariant #6: in-progress sentinel in plan (2 cases)"`:
  - Fixture files: `tests/fixtures/canary/plan-with-sentinel.md` and
    `tests/fixtures/canary/plan-without-sentinel.md`. Both committed
    in this phase's PR. The "with-sentinel" fixture header is a
    comment explaining "this file contains the yellow-circle emoji
    intentionally to test invariant #6 firing; this is a fixture, not
    a real plan."
  - **Fire case:** invoke with
    `--plan-file tests/fixtures/canary/plan-with-sentinel.md` (plus
    empty args for the rest). Assert rc=1, stderr contains
    `INVARIANT-FAIL (#6):`.
  - **Negative case:** same but `--plan-file .../plan-without-sentinel.md`.
    Assert rc=0.

- [ ] Append `section "Invariant #7: main divergence WARN (3 cases)"`:
  - **Case A (no divergence):** fixture creates primary + bare origin
    sharing the same main commit. Invoke (all other args empty).
    Assert rc=0 AND stderr does NOT contain `INVARIANT-WARN (#7):`.
  - **Case B (fetch fails):** fixture with primary repo but origin URL
    set to `file:///nonexistent/canary-origin-b`. Invoke. Assert rc=0
    AND stderr contains
    `INVARIANT-WARN (#7): 'git fetch origin main' failed`.
  - **Case C (tree-identical divergence):** fixture:
    ```bash
    P=$(setup_fixture_repo)
    O=$(setup_bare_origin)
    git -C "$P" remote add origin "$O"
    git -C "$P" commit --allow-empty -m "B"
    git -C "$P" push origin main
    # Now construct B' on origin: same tree as B, different commit metadata
    TREE=$(git -C "$P" rev-parse main^{tree})
    PARENT=$(git -C "$P" rev-parse main^)
    B_PRIME=$(git -C "$O" commit-tree "$TREE" -p "$PARENT" -m "squash-like")
    git -C "$O" update-ref refs/heads/main "$B_PRIME"
    git -C "$P" fetch origin main
    # Now P's main = B; origin/main = B'. Different commits, same tree.
    ```
    Invoke from primary. Assert rc=0 AND stderr contains
    `INVARIANT-WARN (#7): local main has commits absent from origin/main but tree is identical (squash-merge divergence)`.

### Design & Constraints

- All five flags are REQUIRED arguments (unknown-arg check in script).
  Tests pass empty string (`--branch ""` etc.) for irrelevant flags.
- Script resolves MAIN_ROOT via `git rev-parse --git-common-dir`, so
  tests `cd <primary>` before invoking (or use the subshell pattern
  `(cd <primary> && bash <abs-path-to-script> ...)`).
- Invariant #7 is WARN, not FAIL — all three #7 tests assert rc=0.
- Fixture files for invariant #6 are committed to the repo. They do
  NOT trip invariant #6 against THIS plan file at EOP because
  invariant #6 reads only the `--plan-file` arg, not the whole repo.

### Acceptance Criteria

- [ ] Invariant #1: 1 test passes.
- [ ] Invariant #2: 1 test passes.
- [ ] Invariant #3: 2 tests pass (fire + negative).
- [ ] Invariant #4: 2 tests pass (fire + negative).
- [ ] Invariant #5: 2 tests pass (fire + negative).
- [ ] Invariant #6: 2 tests pass; two fixture files committed.
- [ ] Invariant #7: 3 tests pass (no-divergence, fetch-fail,
      squash-merge-divergence), all asserting rc=0.
- [ ] Cumulative canary suite: 40 tests passing (27 + 13).
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (scaffold).

---

## Phase 4 — block-agents.sh reproducers

### Goal

Lock in `hooks/block-agents.sh.template`'s min_model enforcement:
family filter (rejects synthetic), ordinal comparison, floor
enforcement, and auto resolution including the current Sonnet fallback.

### Work Items

- [ ] Add two helpers to the test script (inline at the start of the
      Phase-4 section — they're Agent-tool variants of Phase 1's
      Bash-tool helpers):

  ```bash
  expect_agent_deny_substring() {
    local label="$1" input_json="$2" want="$3" repo_root="$4"
    local result
    result=$(REPO_ROOT="$repo_root" bash "$REPO_ROOT/hooks/block-agents.sh.template" <<<"$input_json" 2>/dev/null) || true
    if [[ "$result" == *'"permissionDecision":"deny"'* && "$result" == *"$want"* ]]; then
      pass "$label"
    else
      fail "$label — want deny with '$want', got: $result"
    fi
  }
  expect_agent_allow() {
    local label="$1" input_json="$2" repo_root="$3"
    local result
    result=$(REPO_ROOT="$repo_root" bash "$REPO_ROOT/hooks/block-agents.sh.template" <<<"$input_json" 2>/dev/null) || true
    if [[ -z "$result" ]]; then
      pass "$label"
    else
      fail "$label — expected empty stdout, got: $result"
    fi
  }
  setup_agent_config() {
    # $1 = json string for min_model config; $2 = tmp repo_root
    local json="$1" root="$2"
    mkdir -p "$root/.claude"
    printf '%s' "$json" > "$root/.claude/zskills-config.json"
  }
  ```

  Note: the second arg to `bash` is the hook path; the hook reads
  `$REPO_ROOT/.claude/zskills-config.json`, so tests set REPO_ROOT to
  the fixture dir, NOT the canary repo root.

- [ ] Append `section "block-agents: family filter rejects synthetic (1 case)"`:
  - Fixture JSONL `tests/fixtures/canary/transcript-synthetic.jsonl`
    (committed, 2 lines):
    ```
    {"model":"claude-opus-4-6"}
    {"model":"<synthetic>"}
    ```
  - Tmp REPO_ROOT with config `{"agents":{"min_model":"auto"}}`.
  - Input JSON (pretty-format for clarity; build as single-line in test):
    ```json
    {"tool_name":"Agent","tool_input":{"subagent_type":"Explore","model":"claude-sonnet-4-6"},"transcript_path":"<abs-path-to-fixture>"}
    ```
  - Assert deny with substring `agents.min_model requires claude-opus-4-6 or higher`.
    (The filter skips `<synthetic>`, so the last haiku/sonnet/opus
    entry — Opus — becomes the effective floor.)

- [ ] Append `section "block-agents: ordinal comparison (6 cases)"`:
  - Matrix — each case uses a fresh tmp REPO_ROOT with the listed
    min_model, and the dispatch model is passed via
    `tool_input.model`. No transcript_path needed (min_model is
    EXPLICIT, not `auto`).

  | min_model | dispatch model | expected | deny substring |
  |-----------|----------------|----------|----------------|
  | `claude-haiku-4-5` | `claude-haiku-4-5-20251001` | allow | — |
  | `claude-haiku-4-5` | `claude-sonnet-4-6` | allow | — |
  | `claude-sonnet-4-6` | `claude-haiku-4-5-20251001` | deny | `agents.min_model requires` |
  | `claude-sonnet-4-6` | `claude-sonnet-4-6` | allow | — |
  | `claude-opus-4-6` | `claude-sonnet-4-6` | deny | `agents.min_model requires` |
  | `claude-opus-4-6` | `claude-opus-4-6` | allow | — |

- [ ] Append `section "block-agents: unknown family passes through (1 case)"`:
  - Config `min_model: claude-sonnet-4-6`. Dispatch model
    `claude-foo-99` (no haiku/sonnet/opus substring). Assert allow.
  - Rationale: locks in the intentional "future-model escape valve"
    (`hooks/block-agents.sh.template:87, :150`).

- [ ] Append `section "block-agents: auto fallback to Sonnet (1 case)"`:
  - Config `min_model: auto`. No `transcript_path` in input JSON
    (or set to empty string).
  - Dispatch model `claude-haiku-4-5-20251001`.
  - Assert deny, substring `agents.min_model requires claude-sonnet-4-6 or higher`.
  - **Rationale:** this locks in the CURRENT fallback-to-Sonnet
    behavior at `hooks/block-agents.sh.template:68-69`. If the
    fallback is ever intentionally changed (e.g., to fail closed to
    Opus), this test must be updated in the same PR — treat the
    update as a design decision with its own review.

- [ ] Append `section "block-agents: auto success path (2 cases)"`:
  - Fixture `tests/fixtures/canary/transcript-opus.jsonl` (1 line
    `{"model":"claude-opus-4-6"}`, committed). Config `min_model: auto`.
  - Case A: dispatch `claude-opus-4-6` → allow.
  - Case B: dispatch `claude-sonnet-4-6` → deny, substring
    `agents.min_model requires claude-opus-4-6 or higher`.

- [ ] Append `section "block-agents: min_model not configured (1 case)"`:
  - Config file present but JSON is `{"agents":{}}` (no min_model key).
  - Dispatch any model (e.g., `claude-haiku-4-5-20251001`). Assert allow.

### Design & Constraints

- HOOK path: `$REPO_ROOT/hooks/block-agents.sh.template` in the CANARY
  repo (i.e., `/workspaces/zskills/hooks/...`). But the script's
  `REPO_ROOT` env var is OVERRIDDEN per-test to point at a fixture
  directory containing `.claude/zskills-config.json` and optional
  `.claude/agents/*.md`.
- Fixture transcripts are committed (not generated at test time) so
  they're reproducible under CI.
- Input JSON built with Python for correctness:
  ```bash
  python3 -c 'import json,sys,os;
    d={"tool_name":"Agent",
       "tool_input":{"subagent_type":"Explore","model":os.environ["MODEL"]},
       "transcript_path":os.environ.get("TPATH","")};
    print(json.dumps(d))'
  ```

### Acceptance Criteria

- [ ] Family filter: 1 test passes.
- [ ] Ordinal comparison: 6 tests pass.
- [ ] Unknown family pass-through: 1 test passes.
- [ ] Auto fallback to Sonnet: 1 test passes.
- [ ] Auto success path: 2 tests pass.
- [ ] Min_model not configured: 1 test passes.
- [ ] Fixture files committed: `transcript-synthetic.jsonl`, `transcript-opus.jsonl`.
- [ ] Cumulative canary suite: 52 tests passing (40 + 12).

### Dependencies

Phase 1 (scaffold).

---

## Phase 5 — /commit reviewer + Phase 7 verification

### Goal

Lock in the verbatim read-only reviewer prompt in `skills/commit/SKILL.md`
and the Phase-7 anti-stash discipline. A future edit that weakens either
must fail the canary.

### Work Items

- [ ] Append `section "/commit reviewer prompt: load-bearing substrings (canonical)"`:
  - Target: `skills/commit/SKILL.md`.
  - Each substring checked via `grep -F -q "<sub>" skills/commit/SKILL.md`:
    - `You are read-only.`
    - `FORBIDDEN:`
    - `git stash`
    - `push/-u/save/bare`
    - `checkout`
    - `restore`
    - `reset`
    - `editing files`
    - `creating worktrees`
    - `git show <commit>:<file>`
    - `Past failure: reviewer ran`
  - 11 tests.

- [ ] Append `section "/commit reviewer prompt: load-bearing substrings (installed copy)"`:
  - Target: `.claude/skills/commit/SKILL.md`.
  - If file absent (fresh-clone scenario): emit one `pass` with label
    `installed copy: SKIPPED (run update-zskills to enable)` — explicit
    skip-notice, NOT silent pass.
  - If file present: run the same 11 grep-F checks against it.

- [ ] Append `section "/commit Phase 7: anti-stash discipline (2 cases)"`:
  - In `skills/commit/SKILL.md`, assert via `grep -F`:
    - `Do NOT stash`
    - `try-without-stash`

- [ ] Append `section "/commit Key Rules: stash prohibition (2 cases)"`:
  - In `skills/commit/SKILL.md`, assert via `grep -c -F`:
    - `Do NOT stash` appears ≥ 2 times (Phase 7 + Key Rules occurrences).
    - `hook blocks` appears ≥ 1 time.
  - Two tests total.

- [ ] Write `reports/plan-canary-failure-injection.md` summarizing:
  - Final test count (either 67 or 57 depending on installed-copy state).
  - Enforcing layers covered (hook: stash + agents; script: land-phase
    + invariants; skill prompt: /commit reviewer + Phase 7).
  - Any follow-up issues filed during execution (link them).
  - One-paragraph user-facing summary: "To verify this zskills install
    catches known silent-failure modes, run `bash tests/run-all.sh`.
    All canary tests passing means the install's hooks, invariant
    scripts, and reviewer prompts match the designed behavior."

- [ ] Update Progress Tracker: mark all 5 rows ✅ with commit SHAs.

### Design & Constraints

- `grep -F` for every substring check — avoids regex gotchas with
  backticks, parens, asterisks. Always quote the argument.
- Canonical file tests are always required.
- Installed copy may be absent on fresh clones. Skip-with-message (not
  silent pass) is the right call.
- No fixture files needed — pure content checks on files already in repo.

### Acceptance Criteria

- [ ] Canonical substrings: 11 tests pass.
- [ ] Installed copy: either 11 tests pass OR 1 SKIP notice passes.
- [ ] Phase 7 anti-stash: 2 tests pass.
- [ ] Key Rules stash prohibition: 2 tests pass.
- [ ] Progress Tracker all 5 rows ✅ with SHAs.
- [ ] `reports/plan-canary-failure-injection.md` exists.
- [ ] Final `bash tests/test-canary-failures.sh` reports
      `78 passed, 0 failed` (installed-copy present: 18+9+13+12+26) or
      `68 passed, 0 failed` (installed-copy skipped: 18+9+13+12+16).
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phase 1 (scaffold).

---

## Verification after completion

When all 5 phases are ✅ on main:

1. `bash tests/test-canary-failures.sh` exits 0 with the expected count.
2. `bash tests/run-all.sh` exits 0 overall.
3. `tests/test-canary-failures.sh` exists at roughly 400-600 lines.
4. `tests/fixtures/canary/` contains: `plan-with-sentinel.md`,
   `plan-without-sentinel.md`, `transcript-synthetic.jsonl`,
   `transcript-opus.jsonl`, and `.gitkeep`.
5. `reports/plan-canary-failure-injection.md` summarizes the suite.
6. Progress Tracker above all ✅.
7. No unrelated changes landed in these 5 PRs.

## Follow-up issues (NOT fixed by this plan)

If execution surfaces any of these, file as separate GitHub issues.
They're out of scope for the canary:

- **`.landed` atomic-write rc check** — sites in
  `skills/commit/SKILL.md:370-376` and `skills/run-plan/SKILL.md` don't
  check `cat` or `mv` exit codes. Defensive coding PR of its own.
- **Invariant #6 scope** — currently whole-file grep; could be scoped
  to tracker-table rows (`^\|.*<sentinel>`). Its own tiny PR.
- **PIPELINE_ID marker-naming convention** — heterogeneous writer
  conventions across skills (TRACKING_ID, integer indices, literal
  strings like `sprint`/`meta`, `$ISSUE_NUMBER`). No reader-side
  one-line fix; needs its own design plan.
- **block-agents.sh auto fallback direction** — current behavior is
  fail-closed to Sonnet. A design discussion separately can decide
  whether Opus should be the fallback. The canary LOCKS in current
  behavior.
- **`gh pr view` rate-limit silent `OPEN` fallback** — retry loop +
  `status: pr-state-unknown` would be safer. Separate hardening PR.
- **`git worktree add` poisoned-branch resume** — silent fallback to
  `git worktree add <path> <branch>` when `-b` fails. Discriminator
  logic (AHEAD=0 or `.worktreepurpose`-tracked) is its own PR.

## Plan Quality

Populated by the implementing agent after each phase lands.
