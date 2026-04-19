---
title: /create-worktree Skill — Unify Worktree Creation Across Skills
created: 2026-04-18
status: active
---

# Plan: /create-worktree Skill — Unify Worktree Creation Across Skills

## Overview

Five zskills skills currently create git worktrees, each re-implementing the
same choreography around `scripts/worktree-add-safe.sh`: prune stale
registrations, ff-merge local `main`, compute a path, create the worktree,
write `.zskills-tracked` so the pipeline hook scopes correctly, optionally
write `.worktreepurpose` as a resume signal, and then dispatch an agent with
a `cd` preamble. Three of the five sites share the same safety helper; two
inline `git worktree add` directly. The duplication is in the surrounding
plumbing, not the `git worktree add` call — which is exactly the kind of
cross-cutting concern that extracts well.

This plan ships `scripts/create-worktree.sh` as the single, shared executable
that owns the full worktree-creation contract, plus a thin skill wrapper
`skills/create-worktree/SKILL.md` that documents the script for
model-driven invocation. All five callers migrate to
`bash "$MAIN_ROOT/scripts/create-worktree.sh" ...` (the same idiom used for
every other shared helper in the repo: `worktree-add-safe.sh`,
`write-landed.sh`, `sanitize-pipeline-id.sh`, `land-phase.sh`). The script
accepts a slug and a set of flags (`--prefix`, `--branch-name`, `--from`,
`--root`, `--purpose`, `--allow-resume`, `--no-preflight`), constructs the
path, invokes `worktree-add-safe.sh`, writes the two required untracked
files, and prints the absolute worktree path to stdout. Callers capture
stdout, `cd` into the printed path, and dispatch their agent. No more
inline `git worktree add`, no more per-caller `.zskills-tracked` echo, no
more accidental divergence between sites.

**Scope check — `/commit` is NOT a worktree-creation site.** `skills/commit/SKILL.md`
has ten `worktree` references but zero `git worktree add` and zero
`worktree-add-safe.sh` invocations. `/commit land` operates on pre-existing
worktrees (cherry-picks their commits to main). Scope remains the five sites
in `run-plan`, `fix-issues`, and `do`. (Per reviewer R-F11 verification.)

**Unit of sharing: a bash script, not a slash command.** In Claude Code, a
slash command is a markdown instruction file loaded into the model's context
via the Skill tool — it is NOT an executable on `PATH`. You cannot write
`WT_PATH=$(/create-worktree ...)` in a bash block; the shell would try to
execute a file at `/create-worktree` that does not exist. Every existing
cross-skill helper in this repo ships as `scripts/*.sh` and is invoked as
`bash scripts/<name>.sh`. `/create-worktree` follows that pattern. The
skill wrapper exists so the model can discover and reason about the tool;
the script is what actually runs. The wrapper is a deliberate precedent:
`worktree-add-safe.sh`, `sanitize-pipeline-id.sh`, `land-phase.sh`, and
`write-landed.sh` ship script-only today; adding a SKILL.md for
`create-worktree` is an experiment in model-driven discoverability that
other scripts may follow if it proves useful (R2-L1).

**Six architectural decisions locked in (from research §3):**

1. **Worktree root.** Default path is `/tmp/${PROJECT_NAME}[-${prefix}]-${slug}`
   (prefix optional). An optional config key `execution.worktree_root` (default
   `/tmp`) overrides the parent directory for teams that want persistent roots.
   Rationale: `/tmp` is the validated convention (CANARY10, EPHEMERAL_TO_TMP,
   `land-phase.sh`); configurability preserves flexibility without a
   migration.

2. **Path prefix is hyphen-safe; branch name is decoupled.** `--prefix <str>`
   flag always contributes a **hyphen-safe** segment to the filesystem path
   (the script rejects slashes in `--prefix`). When a caller needs a branch
   name that differs from the path segment (notably `fix/issue-N`), it passes
   `--branch-name <ref>` to override the derived branch. Path never contains
   slashes; branch may. This decoupling fixes R2-H1 (slash paths break
   `basename "$WORKTREE_PATH"` consumers in `land-phase.sh:82`,
   `run-plan:856`, `verify-changes:235,277` and the hyphen-form literal path
   assertion in `tests/test-hooks.sh:1217`).

3. **Replace vs coexist.** Replace, incrementally — one caller per phase.
   Site 5 (`do`'s sibling `../do-${slug}`) is supported via `--root`
   override. Rationale: no flag-day; each caller verifies independently.

4. **Port allocation.** Out of scope for v1. Rationale: no current zskills
   skill consumes a port at creation time; `.env.worktree` is
   doc-party-specific. Honest scope: v1 has no extension point; adding one
   is its own plan.

5. **Dependency install.** Out of scope for v1. Agent bootstrap happens
   after `cd`. No extension point in v1.

6. **`EnterWorktree` tool.** Not used. Script prints the path to stdout; the
   caller `cd`s. Rationale: zskills' multi-phase orchestration requires the
   orchestrator to stay on `main` and `cd` per phase; `EnterWorktree` is a
   session-level state change incompatible with cross-phase continuity.

Implementing agents **must not revisit these decisions**. If they hit a
concrete blocker, document it and escalate to the user before pivoting.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1a — Ship scripts/create-worktree.sh + skill wrapper + smoke test | ⬚ | | |
| 1b — Full test suite + run-all registration + update-zskills registration | ⬚ | | |
| 2 — Migrate /run-plan (both modes) | ⬚ | | manual CANARY10 re-run (WI 2.8) before phase closure |
| 3 — Migrate /fix-issues and /do (three sites) | ⬚ | | manual `/do`, `/fix-issues` runs (WI 3.8) before phase closure |
| 4 — Docs and cleanup | ⬚ | | |

## Phase 1a — Ship scripts/create-worktree.sh + Skill Wrapper + Smoke Test

### Goal

Ship `scripts/create-worktree.sh` (the executable bash implementation), plus
`skills/create-worktree/SKILL.md` (a thin model-facing wrapper that documents
the script). Mirror the skill to `.claude/skills/`. Extend
`config/zskills-config.schema.json` with the `execution.worktree_root` key.
Add a minimal smoke test `tests/test-create-worktree.sh` that covers fresh
creation and path-exists error (two cases only). All tests pass. No callers
migrated yet; full 20-case test harness and registrations are deferred to
Phase 1b.

### Work Items

- [ ] 1a.1 — Create `scripts/create-worktree.sh` with shebang `#!/bin/bash`,
      `set -eu`, and the argument parser / logic described in Design &
      Constraints. Permissions: `chmod +x scripts/create-worktree.sh`.
- [ ] 1a.2 — Argument parser using the bash-regex / word-boundary idiom from
      `skills/do/SKILL.md:70-92`. Flags:
      `--prefix <str>` (hyphen-safe path segment; slash → rc 5),
      `--branch-name <ref>` (override derived branch; slashes allowed),
      `--from <branch>`,
      `--root <path>`,
      `--purpose <text>`,
      `--allow-resume` (bare switch),
      `--no-preflight` (bare switch; skip fetch+ff-merge).
      Positional: `<slug>` (required, the last non-flag token). Reject:
      slug containing whitespace or shell metachars (`;`, `|`, `&`, `$`,
      backticks, newlines); unknown flags; **slash in `--prefix` value**
      (rc 5, stderr "prefix may not contain `/`; use --branch-name to set
      a slash-bearing branch name independently").
- [ ] 1a.3 — Compute `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)`
      at script start, BEFORE any `cd`. All path resolution uses `MAIN_ROOT`
      as the anchor (not `$PWD`), so invocations from inside a nested worktree
      still resolve `--root ../` against the main-repo parent. If not in a
      git repo, exit 5 with "must be invoked from inside a git repository".
      **Install-integrity check (R2-L4):** verify
      `[ -x "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" ]`; if missing,
      exit 5 with stderr "install-integrity error: scripts/sanitize-pipeline-id.sh
      missing — re-run /update-zskills".
      **PROJECT_NAME non-empty assertion (R2-L5):** after
      `PROJECT_NAME=$(basename "$MAIN_ROOT")`, assert
      `[ -n "$PROJECT_NAME" ]` or exit 5.
- [ ] 1a.4 — Config reader for `execution.worktree_root` using the bash-regex
      pattern in §Design & Constraints. Source: `$MAIN_ROOT/.claude/zskills-config.json`.
      Default `/tmp`. Missing config file → default. Missing key → default.
- [ ] 1a.5 — Path template (exact rules — these are the contract; **path
      NEVER contains slashes** because `--prefix` rejects them):
      - **No `--root`, no `--prefix`:** `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}`
      - **No `--root`, with `--prefix P`:** `${WORKTREE_ROOT}/${PROJECT_NAME}-${P}-${SLUG}`
      - **With `--root R`, no `--prefix`:** `${R}/${SLUG}` (PROJECT_NAME stem skipped)
      - **With `--root R`, with `--prefix P`:** `${R}/${P}-${SLUG}` (prefix stays in leaf)

      Where `PROJECT_NAME=$(basename "$MAIN_ROOT")`. All path values are
      normalized with `realpath -m` at the end so stdout is always absolute.
      Because slashes are rejected in `--prefix`, the path leaf is always a
      single directory entry — safe for `basename "$WORKTREE_PATH"` in
      downstream consumers (`land-phase.sh:82`, `run-plan:856`,
      `verify-changes:235,277`).
- [ ] 1a.6 — Branch-name resolution (independent of path):
      - If `--branch-name <ref>` is provided, use `<ref>` verbatim for
        `git worktree add -b`. Slashes allowed (nested refs under
        `refs/heads/` are legal).
      - Else if `--prefix P` is provided (non-empty), branch is `${P}-${SLUG}`.
      - Else (no `--prefix` or explicit `--prefix ''`), branch is `wt-${SLUG}`.
        The `wt-` fallback prevents collision with the literal branch name
        `main` when slug is a common word.

      **Decoupling rationale (R2-H1).** Separating branch from path means
      `/fix-issues` can request branch `fix/issue-42` while keeping the
      path hyphen-form `/tmp/<project>-fix-issue-42` (matches
      `tests/test-hooks.sh:1217` literal assertion and keeps
      `basename "$WORKTREE_PATH"` uniquely scoped).
- [ ] 1a.7 — Pre-flight block: unless `--no-preflight` was passed, run
      `git worktree prune`, `git fetch origin <BASE>`,
      `git merge --ff-only origin/<BASE>` (where BASE defaults to `main`,
      overridable via `--from`). Run from `MAIN_ROOT`. Every fallible call
      checked (`rc=$?; if [ "$rc" != 0 ]`). Fetch failure → exit 6 with
      stderr "pre-flight fetch failed (retryable)". Merge-conflict /
      non-FF → exit 7 with stderr "pre-flight ff-merge not possible;
      resolve divergence on main". (Codes 6 and 7 are for bash callers
      reading `$?`; skill-tool callers read stderr.) The `--no-preflight`
      switch exists so `/do` worktree mode (which today branches from the
      user's current HEAD without fetching) can preserve its semantics in
      Phase 3 WI 3.3 (R2-M3).
- [ ] 1a.8 — Invoke `bash "$MAIN_ROOT/scripts/worktree-add-safe.sh"
      "$BRANCH" "$WT_PATH" "$BASE"` with `ZSKILLS_ALLOW_BRANCH_RESUME=1`
      exported iff `--allow-resume` was passed. Capture rc into
      `WAS_RC=$?`; do NOT exit yet.
- [ ] 1a.9 — **TOCTOU remap (R2-H3).** After `worktree-add-safe.sh`
      returns:
      ```bash
      if [ "$WAS_RC" -ne 0 ] && [ "$WAS_RC" -ne 2 ] \
          && [ -d "$WT_PATH" ]; then
        # Concurrent race: another caller created the path between our -d
        # check in worktree-add-safe.sh and its `git worktree add`. Remap
        # to rc=2 so callers see consistent path-exists semantics.
        echo "create-worktree: path materialized mid-flight; remapping rc=$WAS_RC to rc=2" >&2
        WAS_RC=2
      fi
      if [ "$WAS_RC" -ne 0 ]; then
        exit "$WAS_RC"
      fi
      ```
      This keeps `worktree-add-safe.sh` pristine (no concurrency fix in the
      shared helper) and honors the test case 18 rc=2 contract for two
      concurrent same-slug invocations.
- [ ] 1a.10 — Post-create artifacts. Sanitize PIPELINE_ID first; fallback
      includes prefix (R2-L3):
      ```bash
      FALLBACK_ID="create-worktree"
      if [ -n "${PREFIX:-}" ]; then
        FALLBACK_ID="${FALLBACK_ID}.${PREFIX}"
      fi
      FALLBACK_ID="${FALLBACK_ID}.${SLUG}"
      RAW_PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-$FALLBACK_ID}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$RAW_PIPELINE_ID")
      printf '%s\n' "$PIPELINE_ID" > "$WT_PATH/.zskills-tracked"
      if [ -n "$PURPOSE" ]; then
        printf '%s\n' "$PURPOSE" > "$WT_PATH/.worktreepurpose"
      fi
      ```
      When `--purpose` is omitted, the script does NOT write `.worktreepurpose`
      — that responsibility stays with the caller/agent (some callers dispatch
      agents that write it themselves; this is a deliberate contract split).
- [ ] 1a.11 — Post-create failure cleanup: if `.zskills-tracked` write fails
      (disk full, permission denied), `git worktree remove --force "$WT_PATH"`
      and exit 8 with stderr "post-create write failed — worktree rolled back".
      This prevents orphan worktrees whose next invocation would bail on rc=2
      path-exists.
- [ ] 1a.12 — Final stdout: `printf '%s\n' "$WT_PATH"`. Exactly one line,
      nothing else on stdout. All progress/log/error output goes to stderr.
      Callers use `WT_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" ... 2>/dev/null)`
      when they want stdout only; they may tee stderr to a log file.
- [ ] 1a.13 — Create `skills/create-worktree/SKILL.md` with YAML frontmatter
      (`name: create-worktree`, `disable-model-invocation: false`,
      `argument-hint: "[--prefix P] [--branch-name REF] [--from B] [--root R] [--purpose TEXT] [--allow-resume] [--no-preflight] <slug>"`,
      `description: ...`). The body is a **thin wrapper**: one-line intent,
      exact invocation pattern (`bash "$MAIN_ROOT/scripts/create-worktree.sh" ...`),
      stdout contract, exit-code table, and pointers to the script for
      details. No business logic in the SKILL.md; the script is the spec.
- [ ] 1a.14 — Mirror the skill source: `rm -rf .claude/skills/create-worktree
      && cp -r skills/create-worktree .claude/skills/create-worktree`.
      Verify: `diff -r skills/create-worktree .claude/skills/create-worktree`
      is empty.
- [ ] 1a.15 — Extend `config/zskills-config.schema.json`: add
      `execution.worktree_root` under `properties.execution.properties`:
      ```json
      "worktree_root": {
        "type": "string",
        "default": "/tmp",
        "description": "Parent directory under which /create-worktree places worktrees. Each worktree becomes ${worktree_root}/${project_name}[-${prefix}]-${slug}.",
        "examples": ["/tmp", "/home/user/.cache/worktrees", "/workspaces/wt"]
      }
      ```
- [ ] 1a.16 — **Smoke test only** — write `tests/test-create-worktree.sh`
      with exactly two cases:
      1. **Fresh creation:** no pre-existing branch/path → rc 0;
         `.zskills-tracked` exists; `STDOUT` equals the computed absolute path.
      2. **Path-exists error:** pre-create the path with a junk file → rc 2;
         `STDOUT` is empty.

      Each test exports `ZSKILLS_PIPELINE_ID=test.create-worktree.$$` before
      invoking. Full 20-case suite lands in Phase 1b. DO NOT register in
      `tests/run-all.sh` yet (that registration happens in Phase 1b along
      with the full harness) — run the smoke test directly:
      `bash tests/test-create-worktree.sh`.

### Design & Constraints

**Argument syntax (verbatim contract).**

```
bash "$MAIN_ROOT/scripts/create-worktree.sh" \
  [--prefix P] [--branch-name REF] [--from B] [--root R] \
  [--purpose TEXT] [--allow-resume] [--no-preflight] \
  <slug>
```

**Path template (worked examples — these are the contract).**

Assume `PROJECT_NAME=myrepo`, `WORKTREE_ROOT=/tmp` (default):

| Invocation | Path | Branch |
|------------|------|--------|
| `... foo` | `/tmp/myrepo-foo` | `wt-foo` |
| `... --prefix cp my-plan-phase-2` | `/tmp/myrepo-cp-my-plan-phase-2` | `cp-my-plan-phase-2` |
| `... --prefix pr foo` | `/tmp/myrepo-pr-foo` | `pr-foo` |
| `... --prefix fix-issue --branch-name fix/issue-42 42` | `/tmp/myrepo-fix-issue-42` | `fix/issue-42` |
| `... --from release-2026 hotfix` | `/tmp/myrepo-hotfix` | `wt-hotfix` |
| `... --prefix '' bar` | `/tmp/myrepo-bar` | `wt-bar` |
| `... --root /workspaces/wt foo` | `/workspaces/wt/foo` | `wt-foo` |
| `... --root /workspaces/wt --prefix cp foo` | `/workspaces/wt/cp-foo` | `cp-foo` |
| `... --prefix do --root ../ my-task` | `${realpath(MAIN_ROOT/../)}/do-my-task` | `do-my-task` |
| `... --prefix do --branch-name "${BP}do-my-task" my-task` | `/tmp/myrepo-do-my-task` | `${BP}do-my-task` |

**Key rule:** With `--root R`, the `${PROJECT_NAME}` stem is SKIPPED and the
path becomes `${R}/${PREFIX}-${SLUG}` (or `${R}/${SLUG}` when `--prefix` is
empty). The prefix STAYS in the leaf segment when present. Worked example:
`/do`'s sibling migration (Phase 3 WI 3.3) uses `--prefix do --root ../` to
get `../do-${SLUG}` — matches today's `../do-${TASK_SLUG}` exactly.

**Decoupled branch naming (R2-H1).** The path segment is derived from
`--prefix` (hyphen-safe, slashes rejected). The branch name is derived
from `--branch-name` if provided, else `${PREFIX}-${SLUG}` (or
`wt-${SLUG}` fallback). This lets `/fix-issues` request branch
`fix/issue-42` while keeping path `/tmp/<project>-fix-issue-42`. The
alternative (tr '/' '-' internally) was rejected: it mangles path
silently and breaks the mental model ("what prefix did I pass?").

**CWD-invariance.** Because path resolution uses `MAIN_ROOT` (computed via
`git rev-parse --git-common-dir`) as the anchor, the script produces
identical output whether invoked from `$MAIN_ROOT`, from a subdirectory, or
from inside a nested worktree. Inside a nested worktree, `git
rev-parse --git-common-dir` still returns the main repo's `.git`, so
`MAIN_ROOT` resolves correctly.

**Exit codes** (propagated from `worktree-add-safe.sh` plus skill-specific):

| Code | Meaning | Retryable |
|------|---------|-----------|
| 0 | Worktree created (fresh, recreated, or resumed) | — |
| 2 | Path already exists (including TOCTOU race remap per WI 1a.9) | No (operator decides) |
| 3 | Poisoned branch (behind base, 0 ahead) | No (delete branch manually) |
| 4 | Branch ahead of base without `--allow-resume` | No (pass flag or delete branch) |
| 5 | Input validation failed (bad slug, slash in `--prefix`, unknown flag, not in git repo, install-integrity) | No |
| 6 | Pre-flight fetch failed | Yes (retry when network returns) |
| 7 | Pre-flight ff-merge not possible (divergent main) | No (resolve divergence first) |
| 8 | Post-create write failed (worktree was rolled back) | Maybe (fix disk/permission, retry) |

Codes 6 and 7 are for bash callers reading `$?`; skill-tool callers read
stderr for human-readable diagnostics.

**File writes.** The script writes, in the created worktree:

- `.zskills-tracked` (required, always) — one line, sanitized PIPELINE_ID.
  Value: `${ZSKILLS_PIPELINE_ID:-create-worktree.${PREFIX:+${PREFIX}.}${SLUG}}`
  routed through `scripts/sanitize-pipeline-id.sh`. Including prefix in
  the fallback disambiguates standalone invocations that share a slug but
  differ in prefix (R2-L3).
- `.worktreepurpose` (optional, iff `--purpose` non-empty) — one line, the
  flag's argument verbatim.

Neither file may be git-tracked. Enforced externally by
`scripts/land-phase.sh:60-89` (`EPHEMERAL_FILES`). Tests assert `git
ls-files` in the worktree does not contain either path.

**Writer-contract split.** With this change, `.worktreepurpose` has two
writers:
- The script writes it when `--purpose TEXT` is passed.
- An agent (via its prompt) writes it otherwise.

Which caller uses which? Phase 2 migrates `/run-plan` PR mode and
cherry-pick mode to pass `--purpose`; Phase 2 WI 2.4 removes the redundant
agent-side write from the shared dispatch block in `run-plan` cherry-pick
mode (where the `worktreepurpose` instruction actually lives — see R2-M1
verification). `/do` and `/fix-issues` today have no agent-side
`.worktreepurpose` write (confirmed by `grep worktreepurpose skills/do/SKILL.md
skills/fix-issues/SKILL.md` — zero agent-prompt matches), so passing
`--purpose` there is purely additive.

**Resume detection is directory-based, not `.worktreepurpose`-based.**
`skills/run-plan/SKILL.md:809` uses `if [ -d "$WORKTREE_PATH" ]` to
distinguish resume from fresh in PR mode. The Round 1 note that "PR mode
uses `.worktreepurpose` for resume" was wrong and is corrected here
(R2-M1).

**Stdout contract.** One line: the absolute worktree path, newline-terminated.
All other output (progress messages, error details, helper stderr) goes to
stderr. Callers use `WT_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" ... 2>/dev/null)`
when they want clean stdout; they may redirect stderr to a log file.

**Config-key read pattern (bash regex; no jq dependency).**

```bash
CFG="$MAIN_ROOT/.claude/zskills-config.json"
WORKTREE_ROOT="/tmp"
if [ -f "$CFG" ]; then
  CFG_CONTENT=$(cat "$CFG")
  if [[ "$CFG_CONTENT" =~ \"worktree_root\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    WORKTREE_ROOT="${BASH_REMATCH[1]}"
  fi
fi
```

### Acceptance Criteria

- [ ] `test -x scripts/create-worktree.sh` (executable).
- [ ] `bash -n scripts/create-worktree.sh` passes (syntax clean).
- [ ] `test -f skills/create-worktree/SKILL.md` and
      `test -f .claude/skills/create-worktree/SKILL.md`.
- [ ] `diff -r skills/create-worktree .claude/skills/create-worktree` is empty.
- [ ] `config/zskills-config.schema.json` contains `execution.worktree_root`
      with default `/tmp`. Verification:
      `grep -q '"worktree_root"' config/zskills-config.schema.json`.
- [ ] `bash tests/test-create-worktree.sh` exits 0 (smoke test: fresh
      creation + path-exists error).
- [ ] Invoking `bash scripts/create-worktree.sh --prefix fix/issue 42`
      returns rc 5 with stderr containing "prefix may not contain" (slash
      rejection verified).
- [ ] Invoking `bash scripts/create-worktree.sh --prefix fix-issue
      --branch-name fix/issue-42 42` succeeds; resulting branch is exactly
      `fix/issue-42`; resulting path contains NO slashes in its leaf
      (`basename "$WT_PATH"` = `<project>-fix-issue-42`).

### Dependencies

None — Phase 1a is foundational.

## Phase 1b — Full Test Suite + run-all Registration + update-zskills Registration

### Goal

Extend the smoke test to a 20-case suite covering all documented behavior
(slash-prefix rejection, decoupled branch naming, CWD-invariance, concurrency,
post-create rollback, etc.). Register the suite in `tests/run-all.sh`.
Register `scripts/create-worktree.sh` in `skills/update-zskills/SKILL.md`
so downstream projects receive the script when they run `/update-zskills`.
All tests pass. Still no callers migrated.

### Work Items

- [ ] 1b.1 — Extend `tests/test-create-worktree.sh` from the 2-case smoke
      test (Phase 1a) to a **20-case suite**. Use
      `/tmp/zskills-tests/$(basename "$(pwd)")` for test state per CLAUDE.md.
      Each test explicitly exports `ZSKILLS_PIPELINE_ID=test.create-worktree.$$`
      before invoking the script. Each test captures stdout with
      `STDOUT=$(bash scripts/create-worktree.sh ... 2>/dev/null)` and asserts
      separately on stdout content, exit code, and side effects. Cases
      enumerated under Acceptance Criteria.
- [ ] 1b.2 — Register the test in `tests/run-all.sh`: add
      `run_suite "test-create-worktree.sh" "tests/test-create-worktree.sh"`
      after line 44 (or adjacent to the other `run_suite` lines; keep
      alphabetical/logical grouping). Without this line the new test file is
      silently skipped — `run-all.sh` does NOT auto-discover.
- [ ] 1b.3 — **Register `scripts/create-worktree.sh` in
      `skills/update-zskills/SKILL.md` (R2-H2).** Three separate edits
      (none of them optional):
      1. **Scripts list (~:303-315).** Add a bullet:
         ```
         - `create-worktree.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for unified worktree creation (path, ff-merge, tracking marker, optional purpose)
         ```
         Keep ordering consistent with siblings (alphabetical or
         dependency-sorted; match existing style).
      2. **Missing-scripts copy step (~:558).** Ensure the copy loop at
         Step D covers `create-worktree.sh` — today it copies missing
         scripts from `$PORTABLE/scripts/`; if the step enumerates scripts
         individually, add the entry. If it uses a glob/loop, no edit is
         needed but add a verification note.
      3. **Install report (~:591).** The "Scripts: N scripts installed"
         report line is count-only; no edit needed unless the enumeration
         elsewhere drives the count. Verify by reading the surrounding
         block.
- [ ] 1b.4 — Mirror the update-zskills edit:
      `rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/update-zskills`.
      Verify: `diff -r skills/update-zskills .claude/skills/update-zskills` is empty.

### Design & Constraints

Test harness invariants are stated in Phase 1a Design. Nothing new here —
this phase is "finish the tests + publish the script to downstream".

**Why split (R2-M5).** Phase 1a+1b together were 16 WIs + 18 test cases.
That exceeded the empirical comfort zone for a single agent phase
(restructuring drift, slower verification, larger rollback unit). Splitting
lets Phase 1a ship a minimally-useful artifact (script + skill + schema +
smoke test) that's independently reviewable; Phase 1b extends coverage and
wires into the distribution surface.

### Acceptance Criteria

- [ ] `bash tests/test-create-worktree.sh` exits 0 with these 20 cases
      (each exports `ZSKILLS_PIPELINE_ID=test.create-worktree.$$` at setup;
      each captures stdout via `STDOUT=$(... 2>/dev/null)`):
  1. **Fresh fresh:** no pre-existing branch/path → rc 0; `.zskills-tracked`
     exists and contains the exported PIPELINE_ID (sanitized); `STDOUT`
     equals the computed absolute path.
  2. **Path-exists error:** pre-create the path with a junk file → rc 2;
     `STDOUT` is empty.
  3. **Poisoned branch:** pre-create a branch behind main with zero ahead
     → rc 3.
  4. **Resume-denied:** branch ahead of main, no `--allow-resume` → rc 4.
  5. **Resume-allowed:** same as 4 but with `--allow-resume` → rc 0;
     existing commits preserved on branch.
  6. **`--prefix cp foo`:** path ends with `-cp-foo`; branch named `cp-foo`.
  7. **`--prefix '' bar` (explicit empty):** path ends with `-bar` (no
     prefix segment); branch named `wt-bar` (collision guard).
  8. **`--root /tmp/custom foo`:** path is exactly `/tmp/custom/foo`
     (PROJECT_NAME stem skipped, no prefix); branch named `wt-foo`.
  9. **`--root ../ --prefix do my-task`:** path is
     `${realpath(MAIN_ROOT/../)}/do-my-task` (prefix stays in leaf, matches
     site-5 migration); branch named `do-my-task`.
  10. **`--from release-x foo`:** merge `--ff-only` uses `origin/release-x`;
      branch based at `release-x`; path is `/tmp/<project>-foo`.
  11. **`--purpose "hello world" foo`:** `.worktreepurpose` contains
      exactly `hello world\n`; `--purpose` omitted → `.worktreepurpose` is
      NOT created by the script.
  12. **Stdout discipline:** `STDOUT` is exactly one line and equals the
      absolute worktree path; stderr (captured separately) contains progress
      messages.
  13. **No accidental tracking:** `git -C "$WT_PATH" ls-files --error-unmatch
      .zskills-tracked .worktreepurpose` returns non-zero (both untracked).
  14. **Whitespace slug:** `scripts/create-worktree.sh "bad slug"` → rc 5,
      stderr contains "slug may not contain whitespace".
  15. **Slash-in-prefix rejected (R2-H1):** `--prefix fix/issue 42` → rc 5,
      stderr contains "prefix may not contain `/`" and mentions
      `--branch-name` as the alternative.
  16. **`--branch-name` override (R2-H1):** `--prefix fix-issue
      --branch-name fix/issue-42 42` → rc 0; `git branch --list
      'fix/issue-42'` prints one line; resulting path is
      `/tmp/<project>-fix-issue-42` (hyphen-safe; no slash in leaf);
      `basename "$STDOUT"` equals `<project>-fix-issue-42`.
  17. **CWD-invariance:** invoke from a subdirectory of `$MAIN_ROOT` AND
      from inside a nested worktree. Both resolve `--root ../ --prefix do
      foo` to the same absolute path (sibling of main-repo parent).
  18. **Concurrent invocations, same slug (R2-H3):** two `bash
      scripts/create-worktree.sh --prefix cp foo` in parallel (`&` and `wait`)
      → exactly one returns rc 0; the other returns rc 2 (path-exists or
      remapped per WI 1a.9); no race corruption (only one branch created,
      worktree state consistent). Verify by post-run
      `git worktree list | grep -c '\-cp-foo$'` ≤ 1. The test explicitly
      exercises the TOCTOU remap by expecting rc=2 from the losing
      process even when `worktree-add-safe.sh` would have returned rc=128.
  19. **Post-create write failure cleanup:** simulate by pre-creating
      `$WT_PATH/.zskills-tracked` as a directory (so `printf >` fails) → rc 8;
      `git worktree list` does NOT contain `$WT_PATH` (rolled back).
  20. **`--no-preflight`:** with local `main` artificially behind origin,
      invoke `--no-preflight foo`; the script does NOT fetch or ff-merge
      (assert via a guard repo where fetching would visibly change
      refs/remotes/origin/main) and succeeds rc=0.

  (20 cases total — keep the numbering as shown.)
- [ ] `grep -c create-worktree tests/run-all.sh` ≥ 1 (test registered).
- [ ] `bash tests/run-all.sh` exits 0 and the output includes a
      `Tests: test-create-worktree.sh` section.
- [ ] `grep -c create-worktree skills/update-zskills/SKILL.md` ≥ 1
      (script listed in install surface; R2-H2). Reviewer target was ≥ 3,
      but editions 2 and 3 (copy-step / install-report) may be
      no-op-by-loop; the unconditional requirement is ≥ 1 bullet in the
      scripts list at `:303-315`. Phase report documents which of the
      three edit sites actually required text changes.
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills` is empty.

### Dependencies

Phase 1a.

## Phase 2 — Migrate /run-plan (Both Modes)

### Goal

Replace the two worktree-creation sites in `skills/run-plan/SKILL.md`
(cherry-pick mode at `:603`, PR mode at `:814`) with
`bash "$MAIN_ROOT/scripts/create-worktree.sh"` calls. Audit and update
run-plan's agent prompts that currently instruct the dispatched agent to
write `.worktreepurpose` (now written by the script). All existing run-plan
tests pass. CANARY10 is re-run manually by the user as a confidence gate.

### Work Items

- [ ] 2.1 — **Cherry-pick site (run-plan:603).** Replace the inline
      `git worktree add -b cp-${PLAN_SLUG}-${PHASE} $WORKTREE_PATH main`
      block plus its surrounding prune/fetch/ff-merge/`.zskills-tracked`
      echo (lines ~590–607) with:
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      WT_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
        --prefix cp \
        --purpose "run-plan cherry-pick; plan=${PLAN_SLUG}; phase=${PHASE}" \
        "${PLAN_SLUG}-phase-${PHASE}")
      rc=$?
      if [ "$rc" -ne 0 ]; then
        echo "create-worktree failed rc=$rc" >&2
        exit "$rc"
      fi
      WORKTREE_PATH="$WT_PATH"
      ```
      Passing `--purpose` here means the script writes `.worktreepurpose`
      and the shared dispatch block's stale instruction (WI 2.4) can be
      removed.
- [ ] 2.2 — **PR site (run-plan:814).** Replace the
      `worktree-add-safe.sh` invocation plus `ZSKILLS_ALLOW_BRANCH_RESUME=1`
      opt-in plus the separate `.zskills-tracked` echo with a single
      `create-worktree.sh` call:
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
        --prefix pr --allow-resume \
        --purpose "run-plan PR mode; plan=${PLAN_SLUG}" \
        "${PLAN_SLUG}")
      ```
      Note: PR-mode resume detection uses `[ -d "$WORKTREE_PATH" ]` at
      `run-plan:809` — it is **directory-based**, not
      `.worktreepurpose`-based. (Round 1 had this wrong; see R2-M1.)
      `create-worktree.sh` adds no new resume semantics beyond what
      `worktree-add-safe.sh` already provides via `--allow-resume`.
- [ ] 2.3 — Remove now-dead code at each site: the pre-flight prune /
      fetch / ff-merge blocks (redundant — `create-worktree.sh` does them),
      the inline `.zskills-tracked` echo, and any duplicated
      `ZSKILLS_ALLOW_BRANCH_RESUME` exports.
- [ ] 2.4 — **Audit and remove stale `.worktreepurpose` agent
      instructions in the cherry-pick shared dispatch block (R2-M1).**
      Verification first:
      ```bash
      awk '/^### / { sec=$0 } /worktreepurpose/ { print NR, sec, $0 }' \
        skills/run-plan/SKILL.md
      ```
      Every hit today is inside `### Worktree mode (default)` — the
      cherry-pick dispatch block around lines 630-647. PR mode has NO
      `.worktreepurpose` agent instructions today. So the work is:
      - DELETE the agent-side instruction at `skills/run-plan/SKILL.md:630-634`
        (the `echo "<session-name or plan-name>: <phase name>" > $WORKTREE_PATH/.worktreepurpose`
        block). Since Phase 2 WI 2.1 passes `--purpose` to the script, the
        file is already written before the agent starts.
      - KEEP the hygiene block at `:638-655` (ephemeral-file rules — still
        applies).
      - Acceptance uses section-scoped grep (R2-L7):
        ```bash
        awk '/^### Worktree mode/,/^### [A-Z]/' skills/run-plan/SKILL.md \
          | grep -c worktreepurpose
        ```
        Expected value: drops from today's 4 matches inside that section
        to at most 2 (hygiene-block references), i.e., the agent
        instruction lines 630-634 are gone but the hygiene/ephemeral-file
        rules remain.
      - Correct the Design narrative: resume in PR mode uses directory
        existence (`:809`), not `.worktreepurpose`. If the plan or the
        Design section earlier claimed otherwise, update it (this plan
        already does; confirm the in-repo SKILL.md doesn't restate the
        false claim in any comment).
- [ ] 2.5 — Mirror `skills/run-plan/` → `.claude/skills/run-plan/` via
      `rm -rf .claude/skills/run-plan && cp -r skills/run-plan .claude/skills/run-plan`.
- [ ] 2.6 — Verification greps:
      `grep -n 'git worktree add' skills/run-plan/SKILL.md` returns zero.
      `grep -n 'worktree-add-safe.sh' skills/run-plan/SKILL.md` returns zero.
      `grep -cn 'scripts/create-worktree.sh' skills/run-plan/SKILL.md` ≥ 2.
- [ ] 2.7 — Run `bash tests/run-all.sh` — must be green.
- [ ] 2.8 — **CANARY10 re-run (user-coordinated, manual).** CANARY10 is
      explicitly a manual canary (`plans/CANARY10_PR_MODE.md:2-3,22-24`) —
      it requires real GitHub state and the user has committed to running
      it manually. The implementer **does not auto-dispatch** CANARY10.
      Instead:
      1. Reset CANARY10 via `/run-plan plans/CANARY10_PR_MODE.md finish auto pr`
         only with explicit user approval at phase-land time.
      2. Write a "Manual CANARY10 re-run requested" note in the phase's
         landing report so the user knows to coordinate.
      3. The automated Phase 2 acceptance gate is `bash tests/run-all.sh` +
         WI 2.9 (fresh cherry-pick). CANARY10 is a secondary confidence
         check; its pass is not a Phase 2 blocker, but its failure (if the
         user runs it and it fails) reverts Phase 2.
      4. **Revert procedure on CANARY10 failure (R2-L2):** if the user
         reports CANARY10 failure, revert with
         `git revert <WI-2.2-commit> <WI-2.1-commit>` (reverse order:
         latest first). Do NOT proceed to Phase 3 until the failure is
         debugged and refixed. The two-commit structure (WI 2.1 and 2.2
         land separately — see §Design) keeps the revert scope clean.
- [ ] 2.9 — Run a fresh cherry-pick `/run-plan` invocation against a
      2-phase test plan (e.g., create a throwaway plan with two trivial
      phases, e.g., "append line to a file") and confirm both phases land
      cleanly via cherry-pick.

### Design & Constraints

**Coordination with `plans/RESTRUCTURE_RUN_PLAN.md`.** That plan's Phase 4
may extract run-plan's mode-specific logic into `skills/run-plan/modes/pr.md`
and `skills/run-plan/modes/cherry-pick.md`. If RESTRUCTURE lands first,
the two migration sites move from `skills/run-plan/SKILL.md:603` and
`:814` to those new files. The call pattern is identical; only the file
path changes. If `/create-worktree` lands first, RESTRUCTURE inherits calls
to the new script for free. No hard blocker either direction.

**Resume detection stays directory-based.** PR mode at
`skills/run-plan/SKILL.md:809` checks `if [ -d "$WORKTREE_PATH" ]` to
distinguish resume from fresh. The script's `.worktreepurpose` write is a
metadata/briefing-readability feature, NOT a resume signal. (Correction
from Round 1 Disposition R-F5 narrative; see R2-M1.)

**Commit granularity and rollback.** WI 2.1 and 2.2 land as **two separate
commits** (one per site). Each is independently reversible via `git revert`.
Run `bash tests/run-all.sh` between commits to confirm no regression in
either mode independently. This makes bisection clean if a downstream
failure surfaces later.

**Absolute-path invocation (R2-M2).** Every snippet computes
`MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` before
invoking `bash "$MAIN_ROOT/scripts/create-worktree.sh"`. This defends
against a future reorg (e.g., RESTRUCTURE_RUN_PLAN Phase 4 extracting
into `modes/pr.md`) that might place a `cd` before the invocation.

### Acceptance Criteria

- [ ] `grep -cn 'git worktree add' skills/run-plan/SKILL.md` returns 0.
- [ ] `grep -cn 'worktree-add-safe.sh' skills/run-plan/SKILL.md` returns 0.
- [ ] `grep -cn 'scripts/create-worktree.sh' skills/run-plan/SKILL.md` ≥ 2.
- [ ] `awk '/^### Worktree mode/,/^### [A-Z]/' skills/run-plan/SKILL.md |
      grep -c worktreepurpose` drops (agent instruction removed; hygiene
      references may remain).
- [ ] `diff -r skills/run-plan .claude/skills/run-plan` is empty.
- [ ] `bash tests/run-all.sh` exits 0 (includes
      `tests/test-canary-failures.sh` 30+ cases and the now-registered
      `tests/test-create-worktree.sh`).
- [ ] Fresh cherry-pick `/run-plan` invocation against a 2-phase test plan
      completes both phases without errors.
- [ ] Phase 2 land commits (≥ 2) include a note referring the user to
      re-run CANARY10 manually; no auto-dispatched CANARY10 run appears
      in the git log.
- [ ] Phase 2 work performed as two separate commits (one per migration
      site); `git log --oneline` shows each WI landed independently.

### Dependencies

Phases 1a and 1b.

## Phase 3 — Migrate /fix-issues and /do (Three Sites)

### Goal

Replace the remaining three worktree-creation sites with
`bash "$MAIN_ROOT/scripts/create-worktree.sh"` calls. Site 5 (sibling path
in /do's worktree mode) uses `--root` override and `--no-preflight` to
preserve today's base-branch semantics. `/fix-issues` uses
`--branch-name fix/issue-N` to preserve existing branch naming while
keeping the path hyphen-safe (R2-H1).

### Work Items

- [ ] 3.1 — **fix-issues PR mode (fix-issues:809).** Replace the block at
      `skills/fix-issues/SKILL.md:791-813` (branch assignment, path
      assignment, prune, `worktree-add-safe.sh` invocation,
      `.zskills-tracked` echo) with:
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
        --prefix fix-issue \
        --branch-name "fix/issue-${ISSUE_NUM}" \
        --allow-resume \
        --purpose "fix-issues; issue=${ISSUE_NUM}" \
        "${ISSUE_NUM}")
      ```
      Branch stays **`fix/issue-${ISSUE_NUM}`** exactly (via
      `--branch-name`, which accepts slashes per Phase 1a WI 1a.6). Path is
      `/tmp/<project>-fix-issue-${ISSUE_NUM}` (hyphen form — matches the
      literal assertion at `tests/test-hooks.sh:1217`). This decoupling is
      the R2-H1 fix: path is hyphen-safe for `basename` consumers;
      branch-name ref still uses the slash form that
      `tests/test-hooks.sh:1207-1210` and `skills/fix-report/SKILL.md:111`
      expect.
      Verification (do these before landing):
      - `grep -n '"/tmp/my-app-fix-issue-42"\|fix/issue-42' tests/test-hooks.sh`
        — must still match all existing assertions.
      - `grep -rn 'basename.*WORKTREE' scripts/ skills/` — confirm no
        consumer gets a slash in the path basename.
- [ ] 3.2 — **do PR mode (do:322).** Replace `skills/do/SKILL.md:316-333`
      (prune, fetch/ff-merge, `worktree-add-safe.sh`, sanitize+echo
      `.zskills-tracked`) with:
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      # Preserve today's branch name: ${BRANCH_PREFIX}do-${TASK_SLUG}
      WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
        --prefix do \
        --branch-name "${BRANCH_PREFIX}do-${TASK_SLUG}" \
        --purpose "do PR mode; task=${TASK_SLUG}" \
        "${TASK_SLUG}")
      ```
      Path becomes `/tmp/<project>-do-${TASK_SLUG}` — same as today. Branch
      is `${BRANCH_PREFIX}do-${TASK_SLUG}` verbatim (with `BRANCH_PREFIX`
      prepended exactly as the caller sets it, potentially empty).

      **Sanitize call retention (R2-M4).** KEEP the existing
      `TASK_SLUG=$(bash scripts/sanitize-pipeline-id.sh "$TASK_SLUG")` at
      `skills/do/SKILL.md:330`. It is defensive and cheap — applies to the
      slug variable that is used both in the branch name and in the
      downstream PIPELINE_ID construction by callers that read the
      variable outside this one-shot worktree creation path. Removing it
      would require an exhaustive audit of all sites that read
      `TASK_SLUG` downstream; the audit-cost vastly exceeds the one sed
      execution's cost. This is a definitive choice: KEEP.
- [ ] 3.3 — **do worktree mode (do:482).** Sibling path — use `--root`
      and `--no-preflight` to preserve today's behavior (R2-M3):
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      # Preserve today's timestamp-suffix collision handler at the caller
      # layer. One retry with timestamp suffix if rc=2.
      ATTEMPT_SLUG="${TASK_SLUG}"
      WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
        --prefix do --root ../ --no-preflight "${ATTEMPT_SLUG}") || rc=$?
      if [ "${rc:-0}" = "2" ]; then
        ATTEMPT_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
        WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
          --prefix do --root ../ --no-preflight "${ATTEMPT_SLUG}")
      fi
      ```
      **Why `--no-preflight` (R2-M3).** Today's `/do` worktree mode at
      `skills/do/SKILL.md:482` calls bare `git worktree add` with NO
      pre-flight fetch and NO ff-merge — it branches from the user's
      current HEAD (which may be a feature branch, not main). Post-
      migration without this flag, the script would fetch and ff-merge
      origin/main, silently changing the base branch from whatever the
      user had checked out to `main`. That's a user-facing behavior shift
      that the user has not signed off on. The `--no-preflight` flag
      preserves today's semantics exactly; a follow-up plan can remove it
      with an explicit user decision.

      The `--root ../` value is resolved against `$MAIN_ROOT` (per Phase
      1a WI 1a.3), NOT against CWD. So even if `/do` is invoked from
      inside a nested worktree, the sibling path lands next to the main
      repo. This fixes a latent CWD-sensitivity bug in today's code
      (`skills/do/SKILL.md:476` uses CWD-relative `../do-${TASK_SLUG}`).
      Resulting path: `${realpath(MAIN_ROOT/../)}/do-${ATTEMPT_SLUG}` — a
      sibling of the main-repo root. Branch: `do-${ATTEMPT_SLUG}`.
- [ ] 3.4 — Remove dead code in each of the three call sites: inline
      prune/fetch/ff-merge, `.zskills-tracked` echoes, inline `git worktree
      add`, direct `worktree-add-safe.sh` invocations, duplicated
      `ZSKILLS_ALLOW_BRANCH_RESUME` exports. (Leave the
      `sanitize-pipeline-id.sh` call at `do:330` per WI 3.2.)
- [ ] 3.5 — Mirror both skills via
      `rm -rf .claude/skills/fix-issues && cp -r skills/fix-issues .claude/skills/fix-issues`
      and same for `do`.
- [ ] 3.6 — Verification greps (all must return 0 matches):
      `grep -n 'git worktree add' skills/fix-issues/SKILL.md skills/do/SKILL.md`;
      `grep -n 'worktree-add-safe.sh' skills/fix-issues/SKILL.md skills/do/SKILL.md`.
      And:
      `grep -cn 'scripts/create-worktree.sh' skills/fix-issues/SKILL.md` ≥ 1;
      `grep -cn 'scripts/create-worktree.sh' skills/do/SKILL.md` ≥ 2 (PR
      mode + worktree mode).
- [ ] 3.7 — Run `bash tests/run-all.sh` — must be green, including
      `tests/test-hooks.sh:1207-1220` which asserts `fix/issue-42` branch
      naming AND `/tmp/my-app-fix-issue-42` path (hyphen form).
- [ ] 3.8 — Manual validations:
      - Run a real `/fix-issues` invocation against a dummy GitHub issue
        (or the most recent closed issue as a dry-run). Confirm branch is
        `fix/issue-<N>` (slash form) and path is
        `/tmp/<project>-fix-issue-<N>` (hyphen form).
      - Run a real `/do "<task>" pr` invocation. Confirm it creates
        `/tmp/<project>-do-<slug>` and branch
        `${BRANCH_PREFIX}do-<slug>`.
      - Run a real `/do "<task>" worktree` invocation. Confirm it creates
        a sibling of the main repo at `../do-<slug>` regardless of invocation
        CWD, AND that the base branch is the user's current HEAD (not
        `main` — `--no-preflight` preserves today's behavior).

### Design & Constraints

**fix/issue- branch preservation via `--branch-name` override (R2-H1).**
Round 1 proposed passing `--prefix fix/issue` to preserve the slash in the
branch name. R2-H1 flagged that this ALSO places a slash in the worktree
PATH, breaking `tests/test-hooks.sh:1217` (literal hyphen-form assertion)
AND corrupting `basename "$WORKTREE_PATH"` scoping in
`scripts/land-phase.sh:82`, `skills/run-plan/SKILL.md:856`, and
`skills/verify-changes/SKILL.md:235,277` — the basename becomes
`issue-42` instead of `<project>-fix-issue-42`, so two projects running
`/fix-issues` on issue 42 simultaneously collide on
`/tmp/zskills-tests/issue-42`. This violates the parallel-pipelines core
guarantee (MEMORY: `feedback_parallel_pipelines_core.md`).

The Round 2 fix decouples: `--prefix fix-issue` (hyphen-safe path segment)
+ `--branch-name fix/issue-${N}` (slash-bearing branch ref). Path is
unambiguously `/tmp/<project>-fix-issue-${N}`; branch is
`fix/issue-${N}`. Phase 1a WI 1a.2 rejects slash in `--prefix` values;
Phase 1a WI 1a.6 accepts slashes in `--branch-name`. Phase 1b test cases
15 and 16 lock both halves.

**Sibling-path semantics (site 5).** `--root` resolves against `$MAIN_ROOT`
(the script computes it via `git rev-parse --git-common-dir`). The script
skips the `${PROJECT_NAME}` stem when `--root` is present; the prefix
still appears in the leaf. So `--prefix do --root ../` + `SLUG=my-task`
yields `${realpath(MAIN_ROOT/../)}/do-my-task`.

**Timestamp-suffix collision handler stays at the caller.** `/do` worktree
mode's timestamp retry is a caller-level semantic. Keep it at the caller;
don't push it into the shared script.

**Rollback.** Each of the three WIs lands as a separate commit and is
independently `git revert`-able.

### Acceptance Criteria

- [ ] `grep -cn 'git worktree add' skills/fix-issues/SKILL.md
      skills/do/SKILL.md` returns 0 for both files.
- [ ] `grep -cn 'worktree-add-safe.sh' skills/fix-issues/SKILL.md
      skills/do/SKILL.md` returns 0 for both files.
- [ ] `grep -cn 'scripts/create-worktree.sh' skills/fix-issues/SKILL.md`
      returns ≥ 1; same for `skills/do/SKILL.md` returns ≥ 2.
- [ ] `diff -r skills/fix-issues .claude/skills/fix-issues` and
      `diff -r skills/do .claude/skills/do` both empty.
- [ ] `bash tests/run-all.sh` exits 0.
      `tests/test-hooks.sh:1207-1210` (`fix/issue-42` branch) passes.
      `tests/test-hooks.sh:1217-1220` (`/tmp/my-app-fix-issue-42` path)
      passes.
- [ ] Manual `/do` invocation in worktree mode creates a sibling worktree
      under `${realpath(MAIN_ROOT/../)}/do-<slug>`; the base branch is
      preserved from the user's current HEAD (not forced to `main`).
- [ ] Manual `/fix-issues` PR-mode invocation creates
      `/tmp/<project>-fix-issue-N` (hyphen) with branch `fix/issue-N`
      (slash) and its PR lands cleanly.
- [ ] Phase 3 work performed as three separate commits (one per site);
      each is independently reversible.

### Dependencies

Phases 1a and 1b (script must exist + distributed via update-zskills).
Independent of Phase 2 (can run in parallel if desired; recommend
sequential for easier bisection).

## Phase 4 — Docs and Cleanup

### Goal

Document the new skill wrapper everywhere that lists zskills skills, retire
any now-duplicated worktree guidance in `CLAUDE_TEMPLATE.md`, and mark this
plan complete.

### Work Items

- [ ] 4.1 — `skills/update-zskills/SKILL.md`: **skill-level** registration
      (script-level was handled in Phase 1b WI 1b.3). Ensure
      `create-worktree` appears wherever skills are enumerated (not
      scripts). If the file enumerates skills by glob/loop, this is a
      no-op; if it hardcodes skill names, add one entry. Verification:
      `grep -c 'create-worktree' skills/update-zskills/SKILL.md` ≥ 2
      (one for the script from Phase 1b; one for the skill here — or
      higher if both the copy-loop and install-report enumerations
      require literal mentions).
- [ ] 4.2 — `CLAUDE_TEMPLATE.md`: if it contains a "Worktree Rules"
      section that enumerates worktree-creating skills or describes the
      creation sequence, update the narrative to reference
      `scripts/create-worktree.sh` (and `/create-worktree` as its
      model-facing entry point). Do NOT remove the isolation rules
      themselves. If the template has no such section, no edit needed.
      Verification: either
      `grep -n 'create-worktree' CLAUDE_TEMPLATE.md` shows at least one
      reference, or a comment in the phase report explains no edit was
      needed because the template lacks that section.
- [ ] 4.3 — `plans/PLAN_INDEX.md`: today this file does NOT exist
      (`ls plans/PLAN_INDEX.md` → no such file). Reframed rule:
      - If the file exists at Phase 4 time, add an entry in the format
        used by other rows (e.g., `CREATE_WORKTREE_SKILL.md — complete`).
      - If the file does not exist, skip this WI — `/plans` will
        auto-rebuild it with the new plan included.
      - Acceptance: either `grep -q 'CREATE_WORKTREE_SKILL' plans/PLAN_INDEX.md`
        succeeds, OR `plans/PLAN_INDEX.md` does not exist.
- [ ] 4.4 — `README.md` / `CHANGELOG.md`: add a one-line entry noting the
      new skill and script. Follow existing style in `CHANGELOG.md`.
- [ ] 4.5 — Mark this plan `status: complete` in its frontmatter.
- [ ] 4.6 — If WI 4.1 modified `skills/update-zskills/SKILL.md`, mirror:
      `rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/update-zskills`.

### Design & Constraints

Docs-only phase. No code changes. No `.claude/skills/` mirror unless WI 4.1
touches `skills/update-zskills/SKILL.md`. Phase 1b already registered the
script in update-zskills; this phase handles the skill-level registration
and the rest of the doc surface.

### Acceptance Criteria

- [ ] `grep -c 'create-worktree' skills/update-zskills/SKILL.md` ≥ 2
      (script from 1b + skill from 4.1, or script-only if enumeration
      is glob/loop-based; phase report documents which).
- [ ] `CLAUDE_TEMPLATE.md` references `create-worktree` if it has a
      worktree section; otherwise a phase-report note explains the skip.
- [ ] `plans/PLAN_INDEX.md` updated or absent (acceptance disjunctively).
- [ ] `CHANGELOG.md` has a new entry line containing `create-worktree`.
- [ ] `head -5 plans/CREATE_WORKTREE_SKILL.md` shows `status: complete`.
- [ ] If WI 4.1 modified update-zskills:
      `diff -r skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] `bash tests/run-all.sh` still exits 0 — docs edits must not break
      anything.

### Dependencies

Phases 1a, 1b, 2, 3.

## Round 1 Disposition

Each of the 20 Round 1 findings was verified by re-running its verification
check against the source tree before acting. Dispositions are recorded below.

| ID | Severity | Evidence | Disposition | Notes |
|----|----------|----------|-------------|-------|
| R-F1 | HIGH | Verified | Fixed | `grep -r '\$(/[a-z-]' skills/` returns zero matches; `research-and-plan/SKILL.md:74-104` confirms Skill tool loads into context (not a subprocess). Plan restructured: primary deliverable is `scripts/create-worktree.sh`, skill is a thin wrapper; every migration snippet uses `bash scripts/create-worktree.sh ...`. Phase 1 title and WIs rewritten accordingly. |
| R-F2 | HIGH | Verified | Fixed | `grep -rn 'fix/issue-' tests/` hit `test-hooks.sh:1206,1207,1208,1210,1229` (not docs/comments as the old draft claimed). `skills/fix-report/SKILL.md:111` also documents slash form. Branch rename removed. Phase 3 WI 3.1 now passes `--prefix fix/issue` to preserve `fix/issue-N`; Phase 1 WI 1.2 explicitly allows slash in prefix; Phase 1 test case 15 locks slash-prefix behavior. |
| R-F3 | HIGH | Verified | Fixed | `grep -n sanitize-pipeline-id plans/CREATE_WORKTREE_SKILL.md` (pre-refine) → 0 matches; `skills/do/SKILL.md:330` shows the correct pattern; `CLAUDE.md` §Tracking mandates sanitization. Phase 1 WI 1.9 now routes the value through `scripts/sanitize-pipeline-id.sh`; unset-behavior specified as `create-worktree.${SLUG}` default. |
| R-F4 | HIGH | Verified | Fixed | `grep -c create-worktree tests/run-all.sh` → 0; `tests/run-all.sh:37-44` hardcodes suites. New WI 1.14 registers the test via `run_suite` line; acceptance criterion `grep -c create-worktree tests/run-all.sh ≥ 1` added. |
| R-F5 | HIGH | Verified | Fixed | `grep -n worktreepurpose skills/run-plan/SKILL.md` hits `:630-634` (literal agent instruction); `grep worktreepurpose skills/do/SKILL.md skills/fix-issues/SKILL.md` shows `/do` has zero matches and `/fix-issues` only cleanup refs (matches DA claim). Phase 2 WI 2.4 adds an explicit audit for run-plan's stale agent prompt. Phase 1 WI 1.9 clarifies: when `--purpose` absent, script does NOT write `.worktreepurpose` (caller/agent retains responsibility). |
| R-F6 | MEDIUM | Verified | Fixed | Internal inconsistency confirmed by reading the draft. Unified rule stated in Phase 1 WI 1.5 + §Design "Path template" worked-examples table. Rule: with `--root`, skip PROJECT_NAME stem but keep prefix in the leaf. Test cases 8 and 9 lock in both the no-prefix + root and the prefix + root cases. Phase 3 WI 3.3 migration uses `--prefix do --root ../` → `${realpath(MAIN_ROOT/../)}/do-${SLUG}`. |
| R-F7 | MEDIUM | Verified | Fixed | Self-contradiction in draft confirmed. Phase 1 WI 1.7 now states explicitly: "BRANCH always has `wt-` prefix when `--prefix` is absent OR empty (prevents collision with `main`). PATH has no prefix segment when `--prefix` is absent OR empty." Test case 7 covers explicit-empty `--prefix ''`. |
| R-F8 | MEDIUM | Verified | Fixed | `plans/CANARY10_PR_MODE.md:2-3,22-24` confirms `status: complete` and manual flag. Phase 2 WI 2.8 rewritten as user-coordinated: implementer does NOT auto-dispatch CANARY10. Automated gate is `tests/run-all.sh` + WI 2.9 fresh cherry-pick run. |
| R-F9 | MEDIUM | Verified | Fixed | `skills/do/SKILL.md:476,482` have no `cd "$MAIN_ROOT"` guard. Phase 1 WI 1.3 now requires `MAIN_ROOT` resolution via `git rev-parse --git-common-dir` BEFORE any `cd`; `--root` resolves against `MAIN_ROOT`, not `$PWD`. Test case 16 asserts CWD-invariance. Phase 3 WI 3.3 explicitly notes this fixes a latent bug in today's `/do`. |
| R-F10 | MEDIUM | Verified | Fixed | Draft rollback said "the migration commit" (singular) for a 2-site migration. Phase 2 §Design "Commit granularity and rollback" now states explicitly: two separate commits (one per site); run `tests/run-all.sh` between commits. Acceptance criterion added: "Phase 2 work performed as two separate commits". Phase 3 mirrored for three commits. |
| R-F11 | MEDIUM | Verified | Justified + documented | `grep -n 'worktree add\|worktree-add-safe' skills/commit/SKILL.md` → zero matches. `/commit` does NOT create worktrees (confirmed by reading `skills/commit/SKILL.md`: `worktree` appears 10 times, all referring to operating on pre-existing worktrees). Added a one-line Overview note: "`/commit` operates on pre-existing worktrees and is not a creation site. Scope remains the five sites in run-plan, fix-issues, and do." No scope expansion needed. |
| R-F12 | MEDIUM | Verified | Fixed | Phase 1 WI 1.13 specifies each test exports `ZSKILLS_PIPELINE_ID=test.create-worktree.$$` at setup and captures stdout with `STDOUT=$(... 2>/dev/null)`. Each acceptance-criteria case reiterates the capture pattern. |
| R-F13 | MEDIUM | No anchor (gap noted in research §4.4) | Fixed | Added test case 17 in Phase 1 acceptance: two concurrent invocations with same slug via `&`/`wait`, verify exactly one rc=0 and one rc=2, and `git worktree list` contains at most one matching entry. |
| R-F14 | LOW | Judgment | Fixed | Added to Phase 1 §Design exit-codes table: "Codes 6 and 7 are for bash callers reading `$?`; skill-tool callers read stderr for human-readable diagnostics." Table split for clarity. |
| R-F15 | LOW | Judgment | Justified | Phase 1 has 16 WIs after refinement (up from 12), reflecting the script-vs-skill split (R-F1), the test-registration WI (R-F4), the post-create-failure cleanup WI (R-F17), and the mirror refinement. Everything remains interdependent; splitting Phase 1 would create a skill that ships with no tests for a commit, which is worse than large-phase discomfort. Leaving as one phase. |
| R-F16 | LOW | Judgment | Fixed | Phase 1 WI 1.15 and Phases 2/3 mirror steps now use the exact idiom `rm -rf .claude/skills/<name> && cp -r skills/<name> .claude/skills/<name>` — no trailing-slash ambiguity, no stale files. |
| R-F17 | LOW | Judgment | Fixed | Phase 1 WI 1.10 added: on post-create write failure, `git worktree remove --force $WT_PATH` and exit 8. Test case 18 asserts no orphan worktree remains after simulated write failure. |
| R-F18 | LOW | Judgment | Fixed | Phase 1 §Design exit-codes table: rc 6 (fetch failed, retryable) and rc 7 (ff-merge not possible, non-retryable) are now separate codes. Callers needing retry logic can branch on rc=6. |
| R-F19 | LOW | Judgment | Fixed | Grepped the plan: "extension point reserved" and `WORKTREE_BOOTSTRAP` appeared only in Overview narrative, not in any work item. Overview rewritten to state honestly: v1 has no port-allocation or bootstrap extension point; adding one is its own plan. Removed the vague "extension point" language. |
| R-F20 | LOW | Verified | Fixed | `ls plans/PLAN_INDEX.md` → file absent today. Phase 4 WI 4.3 reframed: conditional on file existence; acceptance is disjunctive (entry present OR file absent). |

**Structural summary.** The refinement is substantially a rewrite driven by
R-F1: `/create-worktree` is redefined as a bash script (`scripts/create-worktree.sh`)
with a thin model-facing skill wrapper, matching every other shared helper
in the repo. Every migration snippet in Phases 2-3 now uses
`bash scripts/create-worktree.sh ...` — the only invocation mechanism that
actually works in a shell. R-F2 removes an invalid branch-rename proposal
in favor of slash-preserving prefix semantics. R-F3, R-F4, R-F5, R-F9
fill spec gaps that would have caused implementer guessing. R-F6/R-F7
resolve internal contradictions with a single unified path-template rule
(documented with a worked-examples table). R-F8 converts a problematic
"auto-run CANARY10" into user-coordinated manual coordination. R-F10
clarifies commit-granularity rollback. R-F11 scopes `/commit` OUT with a
one-line Overview note. Test coverage expands from 13 to 20 cases to cover
concurrency, slash prefixes, CWD-invariance, and post-create rollback.
Phase 1 grows to 16 WIs; Phases 2-4 adjust mechanically to the new
invocation idiom.

## Round 2 Disposition

Each of the 16 Round 2 findings was verified by re-running its verification
check against the source tree before acting. Dispositions are recorded below.

| ID | Severity | Evidence | Disposition | Notes |
|----|----------|----------|-------------|-------|
| R2-H1 | HIGH | Verified | Fixed | `grep -n 'my-app-fix-issue-42' tests/test-hooks.sh` → `:1217` (hyphen-form literal path assertion confirmed). `grep -rn 'basename.*WORKTREE' scripts/ skills/` → `scripts/land-phase.sh:82`, `skills/run-plan/SKILL.md:856`, `skills/run-plan/SKILL.md:1592`. Round 1's slash-in-prefix decision would have broken all of them. Fix: decouple branch from path. Added `--branch-name <ref>` flag (Phase 1a WI 1a.2, 1a.6); `--prefix` now rejects slashes (Phase 1a WI 1a.2 explicitly); Phase 3 WI 3.1 passes `--prefix fix-issue --branch-name fix/issue-${N}`. Path becomes `/tmp/<project>-fix-issue-${N}` (hyphen, matches test-hooks.sh:1217); branch stays `fix/issue-${N}` (slash, matches test-hooks.sh:1207). Test cases 15 (slash-in-prefix rejected) and 16 (`--branch-name` override) lock both halves. |
| R2-H2 | HIGH | Verified | Fixed | `grep -n create-worktree skills/update-zskills/SKILL.md` → 0 matches (confirmed). Scripts list at `:303-315` is a hardcoded enumeration. Added Phase 1b WI 1b.3 registering the script in three locations: scripts list (`:303-315`), missing-scripts copy (`:558`), and install-report (`:591`); plus mirror in WI 1b.4. Placed in Phase 1b (not Phase 4) so the distribution surface is updated atomically with the script — a downstream `/update-zskills` invocation that happens before Phase 4 will still copy the script. |
| R2-H3 | HIGH | Verified | Fixed | `scripts/worktree-add-safe.sh:10-25` confirmed: the `-d` check (`:12`) and `git worktree add` call (`:22` or `:46` or `:70`) are not atomic. Option (a) chosen: Phase 1a WI 1a.8 captures rc into `WAS_RC`; new WI 1a.9 remaps to rc=2 if git failed AND the path now exists. Keeps `worktree-add-safe.sh` pristine. Test case 18 (renumbered per full-suite list) explicitly verifies the remap by expecting rc=2 from the losing concurrent process. |
| R2-M1 | MEDIUM | Verified | Fixed | `awk '/^### / { sec=$0 } /worktreepurpose/ { print NR, sec, $0 }' skills/run-plan/SKILL.md` → all 4 hits at lines 630, 632, 634, 639 inside `### Worktree mode (default)` (the cherry-pick dispatch block). PR mode (lines 800-815) has zero `.worktreepurpose` references. Also confirmed resume detection in PR mode uses `[ -d "$WORKTREE_PATH" ]` at `:809`, not file presence. Phase 2 WI 2.4 rewritten: delete the instruction at `:630-634` (cherry-pick dispatch), keep hygiene rules, correct Design narrative to say "PR resume is directory-based, not `.worktreepurpose`-based". Acceptance uses section-scoped awk grep per R2-L7. Also passing `--purpose` in Phase 2 WI 2.1 (cherry-pick) ensures the script writes the file the agent was previously writing. |
| R2-M2 | MEDIUM | Judgment | Fixed | Every migration snippet in Phases 2-3 now starts with `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` and invokes `bash "$MAIN_ROOT/scripts/create-worktree.sh" ...`. Robust against future reorgs (e.g., RESTRUCTURE_RUN_PLAN Phase 4 extracting into `modes/pr.md` which might sit after a `cd`). |
| R2-M3 | MEDIUM | Verified | Fixed | `awk 'NR>=465&&NR<=482' skills/do/SKILL.md` confirms worktree mode inlines `git worktree add` with no pre-flight. Option (a) chosen: new `--no-preflight` flag (Phase 1a WI 1a.2, 1a.7). Phase 3 WI 3.3 passes `--no-preflight` to preserve today's behavior (branches from user's current HEAD, no origin/main fetch). Phase 1b test case 20 exercises the flag. The base-branch semantics stay today's; removing `--no-preflight` is a separate, user-facing decision. |
| R2-M4 | MEDIUM | Verified | Fixed | Made definitive: KEEP the `sanitize-pipeline-id.sh` call at `skills/do/SKILL.md:330`. Phase 3 WI 3.2 now states this explicitly with reasoning (defensive + cheap; removing requires exhaustive downstream audit). No conditional language. |
| R2-M5 | MEDIUM | Judgment | Fixed | Phase 1 split into Phase 1a (script + wrapper + schema + mirror + 2-case smoke test, 16 WIs) and Phase 1b (full 20-case suite + run-all registration + update-zskills registration, 4 WIs). Phase 1a is shippable standalone; Phase 1b is additive coverage + distribution. Phases 2, 3, 4 renumbered mechanically; Progress Tracker and Dependencies updated. Total phase count: 5. |
| R2-L1 | LOW | Verified | Fixed | Added one-sentence Overview paragraph: "The wrapper is a deliberate precedent: `worktree-add-safe.sh`, `sanitize-pipeline-id.sh`, `land-phase.sh`, and `write-landed.sh` ship script-only today; adding a SKILL.md for `create-worktree` is an experiment in model-driven discoverability that other scripts may follow if it proves useful." |
| R2-L2 | LOW | Judgment | Fixed | Phase 2 WI 2.8 now includes step 4: "Revert procedure on CANARY10 failure: `git revert <WI-2.2-commit> <WI-2.1-commit>`; do not proceed to Phase 3 until debugged." |
| R2-L3 | LOW | Judgment | Fixed | Phase 1a WI 1a.10 fallback ID is `create-worktree.${PREFIX:+${PREFIX}.}${SLUG}` — prefix is included when non-empty, disambiguating standalone invocations that share a slug across different prefixes. |
| R2-L4 | LOW | Judgment | Fixed | Phase 1a WI 1a.3 adds install-integrity assertion: `[ -x "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" ]` or exit 5. |
| R2-L5 | LOW | Judgment | Fixed | Phase 1a WI 1a.3 adds `[ -n "$PROJECT_NAME" ]` assertion after `PROJECT_NAME=$(basename "$MAIN_ROOT")`. |
| R2-L6 | LOW | Judgment | Applied | Round-1 R-F5 claim re-scored: The narrative "PR mode uses `.worktreepurpose` for resume" was incorrect; R2-M1 and the new Phase 2 WI 2.4 correct it. The Round 1 Disposition row stays "Fixed" for R-F5 (the audit WI was added, which was the correct fix) but is effectively superseded by R2-M1's more-correct framing. The rest of Round 1 R-F rows still stand. No other Round 1 demotions warranted. |
| R2-L7 | LOW | Judgment | Fixed | Phase 2 WI 2.4 acceptance uses `awk '/^### Worktree mode/,/^### [A-Z]/' skills/run-plan/SKILL.md \| grep -c worktreepurpose` for section-scoped counting. |
| R2-L8 | LOW | Judgment | Fixed | Progress Tracker rows for Phase 2 and Phase 3 now annotate "manual ... re-run (WI 2.8)" / "manual ... runs (WI 3.8) before phase closure" so the manual gate is visible at the tracker level, not buried in WI text. |

**Structural summary (Round 2).** Three HIGHs were structural. R2-H1
(slash-in-path) forced the largest change: decoupling branch-name from
path-segment via a new `--branch-name` flag, because Round 1's slash-in-
prefix approach would have broken `basename "$WORKTREE_PATH"` in three
downstream consumers and violated the parallel-pipelines invariant. R2-H2
moves update-zskills registration from Phase 4 up to Phase 1b so the
script is distributable atomically with its debut. R2-H3 adds a
TOCTOU-race remap to `create-worktree.sh` (not to `worktree-add-safe.sh`,
which stays pristine). R2-M1 corrects a Round-1 narrative error: the
`.worktreepurpose` agent instruction lives in cherry-pick mode, not PR
mode, and PR-mode resume is directory-based. R2-M3 adds `--no-preflight`
so `/do` worktree mode preserves its today-behavior base-branch
semantics. R2-M5 splits Phase 1 into 1a+1b to manage scope. Test coverage
grows to 20 cases (includes slash-in-prefix rejection, `--branch-name`
override, `--no-preflight`); Phase count becomes 5.

**Structural note on post-round-2 Phase 1 size.** Phase 1a has 16 WIs +
2 smoke test cases. That's still large, but the 16 WIs are tightly
coupled (single script, single skill file, single schema change); splitting
further would create artificial seams. The heavy test-suite work is
isolated in Phase 1b. If Phase 1a proves too large in practice, Phase 1b
could absorb WIs 1a.9-1a.11 (post-create handling + TOCTOU remap +
rollback) as an easy reshuffling — but doing so preemptively creates a
phase 1a that ships an incomplete script (no concurrency safety, no
rollback), which is worse. Current split is the right balance.

## Plan Quality

**Drafting process:** `/draft-plan` with 3 rounds of adversarial review.
**Convergence:** Converged at round 3 (0 HIGH findings remaining).
**Remaining concerns:** None. Round 3 found 1 MEDIUM (label inconsistency
"18 cases" vs 20 enumerated — fixed inline pre-finalize) and 4 LOW polish
items (stale Round-1 disposition WI numbers, optional Progress Tracker
annotations, grep-count semantics). None gate readiness.

### Round History

| Round | Reviewer | DA | Findings | Fixed | Justified | Unresolved |
|-------|----------|-----|----------|-------|-----------|------------|
| 1 | 11 | 14 | 20 (5 HIGH / 8 MED / 7 LOW) | 18 | 2 | 0 |
| 2 | 7 | 14 | 16 (3 HIGH / 5 MED / 8 LOW) | 15 | 0 | 1 (applied as note) |
| 3 | combined | — | 5 (0 HIGH / 1 MED / 4 LOW) | 1 | 0 | 4 (polish, non-gating) |

### Round-by-round structural changes

- **Round 1 → 2:** R-F1 was plan-killing — the draft used `$(/create-worktree ...)` in bash, which can't work since slash commands aren't executables. Restructured to script-first (`scripts/create-worktree.sh`) with thin skill wrapper. R-F2 reverted a `fix/issue-N` → `fix-issue-N` rename that would have broken `tests/test-hooks.sh`. Multiple contract tightening.
- **Round 2 → 3:** R2-H1 found that preserving `fix/issue-N` branch names meant paths got slashes too — breaking `tests/test-hooks.sh:1216` and `basename "$WORKTREE_PATH"` in land-phase.sh, run-plan, verify-changes. Added `--branch-name` flag to decouple branch from path. R2-H2 added the missing `/update-zskills` registration (Phase 1b WI 1b.3). R2-H3 added a TOCTOU-race rc=2 remap in the wrapper to keep concurrency contract. Phase 1 split into 1a/1b to keep scope bounded.
- **Round 3:** 0 HIGHs, 1 label fix applied inline, 4 non-gating polish items documented.

### Evidence discipline

Every round's findings carried **Verification:** lines. The refiners
re-reproduced cited evidence before acting — R-F11 (/commit worktree
status) and R-F5 `.worktreepurpose` contract verified by grep; R2-H1
path-consumer mapping verified by `grep -rn 'basename.*WORKTREE' scripts/
skills/`; R2-H2 install-list absence verified by
`grep -n create-worktree skills/update-zskills/SKILL.md` → 0. Two rounds
had refiners re-score "Fixed" claims after further review caught stale
dispositions — this cycle was the anti-premature-convergence gate.

### Known judgment calls

- `/commit` scoped out of creation sites (research + verified grep). Documented in Overview.
- Skill-wrapper pattern introduced for `scripts/create-worktree.sh` (`scripts/worktree-add-safe.sh` has no companion skill today). Rationale: model-driven discoverability. Other scripts may follow.
- `sanitize-pipeline-id.sh` call at `do:330` kept (belt-and-suspenders); removal would have required downstream audit exceeding fix cost.
- Phase 1a stays at 16 WIs — splitting to hit a size target would ship an incomplete script without concurrency safety. Documented in Phase 1a Design.
- `/do` worktree-mode base-branch preserved via `--no-preflight` flag rather than accepting the ff-merge-from-main default shift.
