---
title: /create-worktree Skill — Unify Worktree Creation Across Skills
created: 2026-04-18
status: active
---

# Plan: /create-worktree Skill — Unify Worktree Creation Across Skills

## Overview

Ship `scripts/create-worktree.sh` (the executable) plus a thin
`skills/create-worktree/SKILL.md` wrapper, then migrate **five worktree-
creation sites** across three skills to a single shared invocation. The
script owns: prefix-derived path, optional `--branch-name` override, optional
pre-flight prune+fetch+ff-merge (suppressible), `worktree-add-safe.sh` call
with TOCTOU-race remap, sanitized `.zskills-tracked` write, and optional
`.worktreepurpose` write. Callers capture stdout (the absolute path), `cd`,
and dispatch their agent.

**The five sites** (verified `grep -rn 'git worktree add\|worktree-add-safe' skills/`):

| # | File | Anchor | Caller |
|---|------|--------|--------|
| 1 | `skills/run-plan/SKILL.md` | `:608` (cherry-pick `git worktree add` inline) | `/run-plan` cherry-pick mode |
| 2 | `skills/run-plan/SKILL.md` | `:819` (`worktree-add-safe.sh`) | `/run-plan` PR mode |
| 3 | `skills/fix-issues/SKILL.md` | `:809` (`worktree-add-safe.sh`) | `/fix-issues` PR mode |
| 4 | `skills/do/modes/pr.md` | `:43` (`worktree-add-safe.sh`) | `/do` PR mode |
| 5 | `skills/do/modes/worktree.md` | `:23` (sibling-path `git worktree add`) | `/do` worktree mode |

`/commit` is NOT a creation site (zero `git worktree add`/`worktree-add-safe.sh` matches; operates on pre-existing worktrees).

**Six locked decisions:**

1. **Worktree root.** Default `/tmp/${PROJECT_NAME}[-${prefix}]-${slug}`; configurable via new schema key `execution.worktree_root` (default `/tmp`).
2. **Path prefix is hyphen-safe; branch name is decoupled (R2-H1).** `--prefix` rejects slashes (rc 5). `--branch-name <ref>` overrides branch independent of path. Lets `/fix-issues` request branch `fix/issue-42` while keeping path `/tmp/<project>-fix-issue-42` (matches `tests/test-hooks.sh` `/fix-issues PR: per-issue worktree path` literal).
3. **Replace, incrementally.** One caller per phase. Site 5 (sibling) supported via `--root` override.
4. **Out of scope for v1:** port allocation, dependency install, `EnterWorktree` integration. Each is its own future plan.
5. **Unit of sharing is a bash script, not a slash command.** Slash commands are markdown loaded into context — not on `PATH`. Skill wrapper is a thin discoverability layer; the script is the spec.
6. **Implementing agents must not revisit these decisions.** Escalate concrete blockers before pivoting.

## Progress Tracker

| Phase | Status | Commit | Notes |
|-------|--------|--------|-------|
| 1a — Ship scripts/create-worktree.sh + skill wrapper + smoke test | ✅ Done | `17c752f` | 5 files, 578 insertions; 2/2 smoke + 255/255 test-hooks |
| 1b — Full test suite + run-all registration + update-zskills registration | 🟡 In Progress | | |
| 2 — Migrate /run-plan (both modes) | ⬚ | | manual CANARY10 re-run (WI 2.8) before phase closure |
| 3 — Migrate /fix-issues and /do (three sites) | ⬚ | | 2 canaries + CANARY10 + 2 smoke checks (WI 3.8) before phase closure |
| 4 — Docs and cleanup | ⬚ | | |

## Phase 1a — Ship scripts/create-worktree.sh + Skill Wrapper + Smoke Test

### Goal

Ship the executable, the thin SKILL.md wrapper, the schema key, and a 2-case smoke test. No callers migrated yet.

### Work Items

- [ ] 1a.1 — Create `scripts/create-worktree.sh` (`#!/bin/bash`, `set -eu`, `chmod +x`).
- [ ] 1a.2 — Argument parser (bash-regex, idiom from `skills/do/SKILL.md`'s flag-loop). Flags: `--prefix <str>`, `--branch-name <ref>`, `--from <branch>`, `--root <path>`, `--purpose <text>`, `--allow-resume`, `--no-preflight`. Positional: `<slug>` (last non-flag token). Reject (rc 5): whitespace/metachar in slug; unknown flag; **slash in `--prefix`** (stderr "prefix may not contain `/`; use --branch-name to set a slash-bearing branch name independently").
- [ ] 1a.3 — Compute `MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)` BEFORE any `cd`. Anchor all path resolution on `MAIN_ROOT`. Not in git → exit 5. Install-integrity: `[ -x "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" ]` or exit 5 (R2-L4). After `PROJECT_NAME=$(basename "$MAIN_ROOT")`: assert non-empty or exit 5 (R2-L5).
- [ ] 1a.4 — Config reader for `execution.worktree_root` (bash regex; no jq) from `$MAIN_ROOT/.claude/zskills-config.json`. Missing file/key → default `/tmp`.
- [ ] 1a.5 — Apply path template (see §Design table).
- [ ] 1a.6 — Branch resolution: `--branch-name` verbatim if given; else `${PREFIX}-${SLUG}` if `--prefix` non-empty; else `wt-${SLUG}` (collision guard against literal `main`).
- [ ] 1a.7 — Pre-flight (skipped iff `--no-preflight`): from `MAIN_ROOT`, run `git worktree prune`; `git fetch origin <BASE>` (rc≠0 → exit 6, retryable); `git merge --ff-only origin/<BASE>` (rc≠0 → exit 7, divergent main). `BASE` defaults `main`, overridable by `--from`.
- [ ] 1a.8 — Invoke `bash "$MAIN_ROOT/scripts/worktree-add-safe.sh" "$BRANCH" "$WT_PATH" "$BASE"` with `ZSKILLS_ALLOW_BRANCH_RESUME=1` exported iff `--allow-resume`. Capture `WAS_RC=$?`; do NOT exit yet.
- [ ] 1a.9 — **TOCTOU remap (R2-H3).** Verbatim form:
      ```bash
      if [ "$WAS_RC" -ne 0 ] && [ "$WAS_RC" -ne 2 ] && [ -d "$WT_PATH" ]; then
        echo "create-worktree: path materialized mid-flight; remapping rc=$WAS_RC to rc=2" >&2
        WAS_RC=2
      fi
      if [ "$WAS_RC" -ne 0 ]; then exit "$WAS_RC"; fi
      ```
      Keeps `worktree-add-safe.sh` pristine; honors test case 18 rc=2 contract.
- [ ] 1a.10 — Post-create writes. Sanitize PIPELINE_ID first; fallback includes prefix (R2-L3):
      ```bash
      FALLBACK_ID="create-worktree"
      [ -n "${PREFIX:-}" ] && FALLBACK_ID="${FALLBACK_ID}.${PREFIX}"
      FALLBACK_ID="${FALLBACK_ID}.${SLUG}"
      RAW_PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-$FALLBACK_ID}"
      PIPELINE_ID=$(bash "$MAIN_ROOT/scripts/sanitize-pipeline-id.sh" "$RAW_PIPELINE_ID")
      printf '%s\n' "$PIPELINE_ID" > "$WT_PATH/.zskills-tracked"
      [ -n "$PURPOSE" ] && printf '%s\n' "$PURPOSE" > "$WT_PATH/.worktreepurpose"
      ```
      When `--purpose` omitted, script does NOT write `.worktreepurpose` — caller/agent retains responsibility.
- [ ] 1a.11 — Post-create rollback: `.zskills-tracked` write fails → `git worktree remove --force "$WT_PATH"`; exit 8 (stderr "post-create write failed — worktree rolled back"). Prevents orphans.
- [ ] 1a.12 — Final stdout: `printf '%s\n' "$WT_PATH"` — exactly one line. All progress/errors → stderr.
- [ ] 1a.13 — Create `skills/create-worktree/SKILL.md` (frontmatter: `name: create-worktree`, `disable-model-invocation: false`, `argument-hint`, `description`). Body: one-line intent, exact `bash "$MAIN_ROOT/scripts/create-worktree.sh"` invocation pattern, stdout contract, exit-code table, pointer to script. **Thin wrapper**; script is the spec.
- [ ] 1a.14 — Mirror: `rm -rf .claude/skills/create-worktree && cp -r skills/create-worktree .claude/skills/create-worktree`. **Edit only `skills/`; never edit `.claude/skills/` directly** (per MEMORY `feedback_claude_skills_permissions.md`). Same rule applies to every mirror in this plan.
- [ ] 1a.15 — Extend `config/zskills-config.schema.json` with `execution.worktree_root` (string, default `/tmp`, description, examples).
- [ ] 1a.16 — Smoke test `tests/test-create-worktree.sh` — exactly **two cases**: (1) fresh creation rc=0 with stdout=path and `.zskills-tracked` present; (2) path-exists rc=2 with empty stdout. Each test exports `ZSKILLS_PIPELINE_ID=test.create-worktree.$$`. Run directly (`bash tests/test-create-worktree.sh`). NOT yet registered in `run-all.sh`.

### Design & Constraints

**CWD-invariance (single source of truth — referenced by all phases).** `MAIN_ROOT` is computed via `git rev-parse --git-common-dir` BEFORE any `cd`. All path resolution (including `--root` relatives) anchors on `MAIN_ROOT`. Inside a nested worktree, `--git-common-dir` still returns the main repo's `.git`, so resolution is identical regardless of invocation CWD. This is the single statement; later phases reference it without restating.

**Argument syntax (verbatim contract).**

```
bash "$MAIN_ROOT/scripts/create-worktree.sh" \
  [--prefix P] [--branch-name REF] [--from B] [--root R] \
  [--purpose TEXT] [--allow-resume] [--no-preflight] \
  <slug>
```

**Path template.** `PROJECT_NAME=$(basename "$MAIN_ROOT")`; `realpath -m` final value:

| Invocation form | Resulting path | Branch |
|---|---|---|
| `... <slug>` | `${WORKTREE_ROOT}/${PROJECT_NAME}-${SLUG}` | `wt-${SLUG}` |
| `... --prefix P <slug>` | `${WORKTREE_ROOT}/${PROJECT_NAME}-${P}-${SLUG}` | `${P}-${SLUG}` |
| `... --root R <slug>` | `${R}/${SLUG}` (PROJECT_NAME stem skipped) | `wt-${SLUG}` |
| `... --root R --prefix P <slug>` | `${R}/${P}-${SLUG}` (prefix stays in leaf) | `${P}-${SLUG}` |

Slashes in `--prefix` rejected (rc 5) → leaf is always a single directory entry → safe for `basename "$WORKTREE_PATH"` consumers (`scripts/land-phase.sh:82`, `skills/run-plan/SKILL.md:856`, `skills/verify-changes/SKILL.md:235,277`).

`--branch-name <ref>` overrides branch independent of path; slashes in branch are legal (refs under `refs/heads/`).

**Exit codes** (propagated from `worktree-add-safe.sh` plus skill-specific):

| Code | Meaning | Retryable |
|------|---------|-----------|
| 0 | Worktree created (fresh, recreated, or resumed) | — |
| 2 | Path exists (incl. TOCTOU remap per WI 1a.9) | No (operator decides) |
| 3 | Poisoned branch (behind base, 0 ahead) | No |
| 4 | Branch ahead of base without `--allow-resume` | No |
| 5 | Input validation (bad slug, slash in `--prefix`, unknown flag, not in git, install-integrity) | No |
| 6 | Pre-flight fetch failed | Yes |
| 7 | Pre-flight ff-merge not possible (divergent main) | No |
| 8 | Post-create write failed (rolled back) | Maybe |

Codes 6/7 differentiated for callers branching on retry semantics. Bash callers read `$?`; skill-tool callers read stderr.

**File writes.** `.zskills-tracked` (always) and `.worktreepurpose` (iff `--purpose`). Neither git-tracked; enforced externally by `scripts/land-phase.sh` (`EPHEMERAL_FILES`). Test case 13 asserts via `git ls-files`.

**`--no-preflight` rationale (R2-M3).** `/do` worktree mode (site 5) currently calls bare `git worktree add` from the user's current HEAD with no fetch/ff-merge. Migrating without this flag would silently shift the base to `origin/main`. The flag preserves today's semantics; removing it is a separate user-facing decision.

### Acceptance Criteria

- [ ] `test -x scripts/create-worktree.sh` and `bash -n scripts/create-worktree.sh` clean.
- [ ] Skill mirror: `diff -r skills/create-worktree .claude/skills/create-worktree` empty.
- [ ] `grep -q '"worktree_root"' config/zskills-config.schema.json`.
- [ ] `bash tests/test-create-worktree.sh` exits 0 (smoke: fresh + path-exists).

### Dependencies

None.

## Phase 1b — Full Test Suite + run-all + update-zskills Registration

### Goal

Extend smoke test → 20-case suite. Register in `tests/run-all.sh`. Register `scripts/create-worktree.sh` in update-zskills so downstream installs pick it up.

### Work Items

- [ ] 1b.1 — Extend `tests/test-create-worktree.sh` to **20 cases** (enumerated in Acceptance). Use `/tmp/zskills-tests/$(basename "$(pwd)")` per CLAUDE.md. Each test exports `ZSKILLS_PIPELINE_ID=test.create-worktree.$$` and captures stdout via `STDOUT=$(... 2>/dev/null)`.
- [ ] 1b.2 — Register in `tests/run-all.sh`: add `run_suite "test-create-worktree.sh" "tests/test-create-worktree.sh"` in the suite block, alphabetical with siblings.
- [ ] 1b.3 — **Register the script in `skills/update-zskills/SKILL.md` (R2-H2).** Single edit: add a bullet to the shared-helpers list at `skills/update-zskills/SKILL.md:448-452` (alongside `worktree-add-safe.sh`, `land-phase.sh`, `write-landed.sh`, `sanitize-pipeline-id.sh`):
      ```
      - `create-worktree.sh` — referenced by `/run-plan`, `/fix-issues`, `/do` for unified worktree creation
      ```
      The "three locations" framing (Round 2 narrative) was wrong: only the bullet list at :448-452 enumerates these helpers individually; copy/install steps use globs/loops and need no edit. Verify with `grep -n create-worktree skills/update-zskills/SKILL.md`.
- [ ] 1b.4 — Mirror update-zskills: `rm -rf .claude/skills/update-zskills && cp -r skills/update-zskills .claude/skills/update-zskills`.

### Design & Constraints

Test invariants stated in Phase 1a §Design. Phase split rationale (R2-M5): 1a ships a minimally-useful artifact (script + skill + schema + smoke); 1b extends coverage and wires distribution.

### Acceptance Criteria

- [ ] `bash tests/test-create-worktree.sh` exits 0 with these 20 cases:

  **Cases 1-13 (foundational coverage — summarized).** 13 cases cover: path-template variants (one row per Phase 1a Design table = 4 base, plus `--from`, `--prefix ''`, `--purpose` set/unset, `--root` absolute vs relative — 8 path/branch combinations); exit codes 0/2/3/4/5 (fresh/path-exists/poisoned/resume-denied/resume-allowed/whitespace-slug); stdout discipline (single-line absolute path, all logs to stderr); no-tracking assertion (`git ls-files` rejects `.zskills-tracked` and `.worktreepurpose`).

  **Cases 14-20 (named regression guards — KEEP VERBATIM with anchors):**

  14. **Whitespace slug (R-F12 stdin discipline):** `scripts/create-worktree.sh "bad slug"` → rc 5; stderr contains "slug may not contain whitespace".
  15. **Slash-in-prefix rejected (R2-H1):** `--prefix fix/issue 42` → rc 5; stderr contains "prefix may not contain `/`" and mentions `--branch-name` as the alternative.
  16. **`--branch-name` override (R2-H1):** `--prefix fix-issue --branch-name fix/issue-42 42` → rc 0; `git branch --list 'fix/issue-42'` prints one line; resulting path `/tmp/<project>-fix-issue-42` (hyphen-safe, no slash in leaf); `basename "$STDOUT"` equals `<project>-fix-issue-42`.
  17. **CWD-invariance (R-F9):** invoke from `$MAIN_ROOT`, from a subdirectory, AND from inside a nested worktree. All three resolve `--root ../ --prefix do foo` to the same absolute path (sibling of main-repo parent).
  18. **Concurrent same-slug invocations (R2-H3):** two `bash scripts/create-worktree.sh --prefix cp foo` in parallel (`&` + `wait`) → exactly one rc 0, one rc 2 (path-exists or remapped per WI 1a.9); `git worktree list | grep -c '\-cp-foo$'` ≤ 1. Test asserts the losing process returns rc=2 even when underlying `worktree-add-safe.sh` would have returned rc=128.
  19. **Post-create write failure rollback (R-F17):** pre-create `$WT_PATH/.zskills-tracked` as a directory so `printf >` fails → rc 8; `git worktree list` does NOT contain `$WT_PATH`.
  20. **`--no-preflight` (R2-M3):** with local `main` artificially behind origin, invoke `--no-preflight foo`; the script does NOT fetch or ff-merge (assert via guard repo where fetching would visibly change `refs/remotes/origin/main`); succeeds rc=0.

- [ ] `grep -c create-worktree tests/run-all.sh` ≥ 1.
- [ ] `bash tests/run-all.sh` exits 0 and output includes a `Tests: test-create-worktree.sh` section.
- [ ] `grep -c create-worktree skills/update-zskills/SKILL.md` ≥ 1 (script bullet at :448-452).
- [ ] `diff -r skills/update-zskills .claude/skills/update-zskills` empty.

### Dependencies

Phase 1a.

## Phase 2 — Migrate /run-plan (Both Modes)

### Goal

Replace the two `/run-plan` worktree-creation sites (cherry-pick at `skills/run-plan/SKILL.md:608`, PR at `:819`) with `create-worktree.sh` calls. Audit and remove the stale `.worktreepurpose` agent instruction in cherry-pick mode (PR mode has none).

**Coordination.** `plans/RESTRUCTURE_RUN_PLAN.md` landed 2026-04-19 (`status: complete`). Worktree-creation blocks were NOT extracted into `skills/run-plan/modes/`; they remain at `SKILL.md:608` and `:819` (verified `grep -n 'git worktree add\|worktree-add-safe' skills/run-plan/SKILL.md skills/run-plan/modes/*.md`).

### Work Items

- [ ] 2.1 — **Cherry-pick site (`skills/run-plan/SKILL.md:608`).** Replace the inline `git worktree add` block plus surrounding prune/fetch/ff-merge/`.zskills-tracked` echo with one `WT=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" --prefix cp --purpose "run-plan cherry-pick; plan=${PLAN_SLUG}; phase=${PHASE}" "${PLAN_SLUG}-phase-${PHASE}")` invocation; assign to `WORKTREE_PATH`; check rc and exit on failure. Compute `MAIN_ROOT` first. Passing `--purpose` here means the script writes `.worktreepurpose` — the redundant agent-side write (WI 2.4) can be removed.
- [ ] 2.2 — **PR site (`skills/run-plan/SKILL.md:819`).** Replace the `worktree-add-safe.sh` invocation + `ZSKILLS_ALLOW_BRANCH_RESUME=1` opt-in + separate `.zskills-tracked` echo with one `WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" --prefix pr --allow-resume --purpose "run-plan PR mode; plan=${PLAN_SLUG}" "${PLAN_SLUG}")` invocation. PR-mode resume detection stays directory-based at the surrounding `if [ -d "$WORKTREE_PATH" ]` check (R2-M1 correction).
- [ ] 2.3 — Remove now-dead code at each site: pre-flight prune/fetch/ff-merge, inline `.zskills-tracked` echo, duplicated `ZSKILLS_ALLOW_BRANCH_RESUME` exports.
- [ ] 2.4 — **Audit and remove stale `.worktreepurpose` agent instruction in cherry-pick dispatch block (R2-M1).** All `worktreepurpose` hits in `skills/run-plan/SKILL.md` are inside `### Worktree mode (default)` (cherry-pick), specifically `:635-639` (the `echo "<session-name or plan-name>: <phase name>" > $WORKTREE_PATH/.worktreepurpose` instruction). PR mode has zero `.worktreepurpose` references. DELETE the agent instruction at `:635-639`; KEEP the hygiene/ephemeral-file rules (`:644-655` area). Section-scoped acceptance: `awk '/^### Worktree mode/,/^### [A-Z]/' skills/run-plan/SKILL.md | grep -c worktreepurpose` drops (4 → ≤2; hygiene refs may remain).
- [ ] 2.5 — Mirror: `rm -rf .claude/skills/run-plan && cp -r skills/run-plan .claude/skills/run-plan`.
- [ ] 2.6 — Verification: `grep -rn 'git worktree add' skills/run-plan/` = 0; `grep -rn 'worktree-add-safe.sh' skills/run-plan/` = 0; `grep -rcn 'scripts/create-worktree.sh' skills/run-plan/` ≥ 2 (recursive — defensive against future modes/ extraction).
- [ ] 2.7 — `bash tests/run-all.sh` green.
- [ ] 2.8 — **CANARY10 re-run (user-coordinated, manual).** CANARY10 (`plans/CANARY10_PR_MODE.md:2-3,22-24`) is explicitly manual. Implementer does NOT auto-dispatch. Phase report includes a "Manual CANARY10 re-run requested" note. Automated gate is `tests/run-all.sh` + WI 2.9. **Revert procedure on user-reported CANARY10 failure (R2-L2):** `git revert <WI-2.2-commit> <WI-2.1-commit>` (reverse order). Two-commit structure (WI 2.1 + 2.2 land separately) keeps revert clean.
- [ ] 2.9 — Run a fresh cherry-pick `/run-plan` invocation against a 2-phase throwaway plan; confirm both phases land cleanly.

### Design & Constraints

(CWD-invariance: see Phase 1a §Design.) Each migration snippet computes `MAIN_ROOT` then invokes via absolute path (`bash "$MAIN_ROOT/scripts/create-worktree.sh"`) — defends against any future reorg that places `cd` before the call (R2-M2).

**Commit granularity.** WIs 2.1 and 2.2 land as **two separate commits**. Run `tests/run-all.sh` between commits.

### Acceptance Criteria

- [ ] `grep -rcn 'git worktree add' skills/run-plan/` = 0.
- [ ] `grep -rcn 'worktree-add-safe.sh' skills/run-plan/` = 0.
- [ ] `grep -rcn 'scripts/create-worktree.sh' skills/run-plan/` ≥ 2.
- [ ] `awk '/^### Worktree mode/,/^### [A-Z]/' skills/run-plan/SKILL.md | grep -c worktreepurpose` drops (agent instruction gone).
- [ ] `diff -r skills/run-plan .claude/skills/run-plan` empty.
- [ ] `bash tests/run-all.sh` exits 0.
- [ ] Two separate commits visible in `git log --oneline` (one per migration site).
- [ ] Phase report contains the manual-CANARY10 note (no auto-dispatched run in git log).

### Dependencies

Phases 1a, 1b.

## Phase 3 — Migrate /fix-issues and /do (Three Sites)

### Goal

Replace the remaining three worktree-creation sites:
- `skills/fix-issues/SKILL.md:809` (PR mode `worktree-add-safe.sh`).
- `skills/do/modes/pr.md:43` (PR mode `worktree-add-safe.sh`) — **note: lives in `do/modes/pr.md`, not `do/SKILL.md`**, post-RESTRUCTURE.
- `skills/do/modes/worktree.md:23` (sibling-path inline `git worktree add`) — **note: lives in `do/modes/worktree.md`**, post-RESTRUCTURE.

### Work Items

- [ ] 3.1 — **fix-issues PR mode (`skills/fix-issues/SKILL.md:809`).** Replace the surrounding block (branch+path assignment, prune, `worktree-add-safe.sh` call, `.zskills-tracked` echo) with one `WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" --prefix fix-issue --branch-name "fix/issue-${ISSUE_NUM}" --allow-resume --purpose "fix-issues; issue=${ISSUE_NUM}" "${ISSUE_NUM}")`. Compute `MAIN_ROOT` first. Branch stays `fix/issue-${ISSUE_NUM}` (slash form via `--branch-name`); path is `/tmp/<project>-fix-issue-${ISSUE_NUM}` (hyphen form). This decoupling is the R2-H1 fix: matches the `tests/test-hooks.sh` literal assertions in the `/fix-issues PR: per-issue branch naming` and `/fix-issues PR: per-issue worktree path` cases (test names are the stable anchors; line numbers drift).
- [ ] 3.2 — **/do PR mode (`skills/do/modes/pr.md:43`).** Replace the `worktree-add-safe.sh` block (Steps A4/A5 in `do/modes/pr.md:36-55`) with one `WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" --prefix do --branch-name "${BRANCH_PREFIX}do-${TASK_SLUG}" --purpose "do PR mode; task=${TASK_SLUG}" "${TASK_SLUG}")`. Compute `MAIN_ROOT` first. Path becomes `/tmp/<project>-do-${TASK_SLUG}`; branch is `${BRANCH_PREFIX}do-${TASK_SLUG}` verbatim. **KEEP** the existing `TASK_SLUG=$(bash scripts/sanitize-pipeline-id.sh "$TASK_SLUG")` defensive sanitize call (R2-M4 — definitive: removing requires exhaustive downstream audit of `TASK_SLUG` consumers).
- [ ] 3.3 — **/do worktree mode (`skills/do/modes/worktree.md:17,21,23`).** Sibling-path migration with `--root ../` and `--no-preflight` (preserves today's base-branch semantics — R2-M3). Replace the inline `git worktree add` and surrounding setup with:
      ```bash
      MAIN_ROOT=$(cd "$(git rev-parse --git-common-dir)/.." && pwd)
      ATTEMPT_SLUG="${TASK_SLUG}"
      rc=0
      WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
        --prefix do --root ../ --no-preflight "${ATTEMPT_SLUG}") || rc=$?
      if [ "${rc:-0}" = "2" ]; then
        ATTEMPT_SLUG="${TASK_SLUG}-$(date +%s | tail -c 5)"
        WORKTREE_PATH=$(bash "$MAIN_ROOT/scripts/create-worktree.sh" \
          --prefix do --root ../ --no-preflight "${ATTEMPT_SLUG}")
      fi
      ```
      The `rc=0` line BEFORE the first invocation is mandatory (R-M2 — fixes a leak where a stale `rc=2` from earlier shell scope would falsely trigger the retry block even when the first invocation succeeded). The `--root ../` resolves against `$MAIN_ROOT` (Phase 1a CWD-invariance), fixing a latent CWD-sensitivity bug in today's `skills/do/modes/worktree.md:17,21` which uses CWD-relative paths. Resulting path: `${realpath(MAIN_ROOT/../)}/do-${ATTEMPT_SLUG}`. Branch: `do-${ATTEMPT_SLUG}`.
- [ ] 3.4 — Remove dead code in each site: inline prune/fetch/ff-merge, `.zskills-tracked` echoes, inline `git worktree add`, direct `worktree-add-safe.sh` invocations, duplicated `ZSKILLS_ALLOW_BRANCH_RESUME` exports. (Keep `sanitize-pipeline-id.sh` at `skills/do/modes/pr.md:51` per WI 3.2.)
- [ ] 3.5 — Mirror both: `rm -rf .claude/skills/fix-issues && cp -r skills/fix-issues .claude/skills/fix-issues`; same for `do` (the `cp -r` is recursive — covers `modes/`).
- [ ] 3.6 — Verification (recursive, covers `do/modes/`): `grep -rcn 'git worktree add' skills/fix-issues/ skills/do/` = 0 for functional matches (a documentation reference to the literal phrase in `skills/do/SKILL.md:437` may remain; greps must filter). `grep -rcn 'worktree-add-safe.sh' skills/fix-issues/ skills/do/` = 0. `grep -rcn 'scripts/create-worktree.sh' skills/fix-issues/` ≥ 1; `grep -rcn 'scripts/create-worktree.sh' skills/do/` ≥ 2 (PR mode in `modes/pr.md` + worktree mode in `modes/worktree.md`).
- [ ] 3.7 — `bash tests/run-all.sh` green — including the `/fix-issues PR: per-issue branch naming` and `/fix-issues PR: per-issue worktree path` test cases in `tests/test-hooks.sh` (literal `fix/issue-42` and `/tmp/my-app-fix-issue-42` checks).
- [ ] 3.8 — Manual validation via dedicated canary plans and smoke checks. Automated tests cover unit/structural correctness; canaries exercise end-to-end behavior that unit tests miss. Required for phase closure.

      **Five failure modes Phase 3 must guard against** (identified in refine-plan round 1):
      1. `/do` worktree-mode base-branch shift — `--no-preflight` miswired, worktree silently branches from `origin/main` not user's HEAD.
      2. Resume semantics mismatch under `ZSKILLS_ALLOW_BRANCH_RESUME=1` — `create-worktree.sh`'s rc=2/rc=4 doesn't mirror `worktree-add-safe.sh`'s.
      3. Stale `.worktreepurpose` agent-dispatch prompts — double-write or clash after WI 2.4 audit.
      4. `rc=0` leak in retry scopes — caught and patched in refine-plan round 1; similar subtle bugs may remain.
      5. `/run-plan` self-migration — Phase 2 migrates `/run-plan` itself; if broken, subsequent phases can't self-dispatch.

      **Validation steps** (run manually — these are procedures, not `/run-plan`-invokable):
      - **`plans/CANARY_DO_WORKTREE_BASE.md`** — manually execute each WI. Guards failure mode 1.
      - **`plans/CANARY_FIX_ISSUES_RESUME.md`** — manually execute each WI. Guards failure mode 2.
      - **`/run-plan plans/CANARY10_PR_MODE.md finish auto pr`** — agent-runnable (CANARY10 is structured for it). Guards failure modes 3 and 5.
      - **Smoke check 1:** `/fix-issues` against a dummy issue → branch `fix/issue-<N>` (slash), path `/tmp/<project>-fix-issue-<N>` (hyphen). Decoupling preserved.
      - **Smoke check 2:** `/do "<task>" pr` → `/tmp/<project>-do-<slug>`, branch `${BRANCH_PREFIX}do-<slug>`. PR-mode migration intact.

      Failure mode 4 (rc=0 leak) has no dedicated canary — `create-worktree.sh` Phase 1a test case 18 structurally prevents recurrence.

      All three canaries + two smoke checks must PASS before Phase 3 is marked ✅. Failure of any → revert Phase 3 commits, file bug.

### Design & Constraints

(CWD-invariance: see Phase 1a §Design. Decoupled branch/path: see Overview decision 2.)

**Sibling-path semantics.** `--root` resolves against `$MAIN_ROOT`; with `--root` present, `${PROJECT_NAME}` stem is skipped, prefix stays in leaf. So `--prefix do --root ../` + `SLUG=task` → `${realpath(MAIN_ROOT/../)}/do-task`.

**Timestamp-suffix collision handler stays at the caller.** It's a `/do`-specific semantic; not shared.

**Commit granularity.** Three separate commits, one per site. Each independently `git revert`-able.

### Acceptance Criteria

- [ ] `grep -rcn 'worktree-add-safe.sh' skills/fix-issues/ skills/do/` = 0.
- [ ] `grep -rcn 'scripts/create-worktree.sh' skills/fix-issues/` ≥ 1.
- [ ] `grep -rcn 'scripts/create-worktree.sh' skills/do/` ≥ 2.
- [ ] `diff -r skills/fix-issues .claude/skills/fix-issues` empty; same for `do`.
- [ ] `bash tests/run-all.sh` exits 0; `/fix-issues PR: per-issue branch naming` and `/fix-issues PR: per-issue worktree path` pass.
- [ ] Manual `/do` worktree-mode invocation creates sibling under `${realpath(MAIN_ROOT/../)}/do-<slug>` with base preserved from user's HEAD.
- [ ] Manual `/fix-issues` PR-mode invocation lands cleanly with hyphen path + slash branch.
- [ ] Three separate commits (one per site) in `git log --oneline`.

### Dependencies

Phases 1a, 1b. Independent of Phase 2 (parallel possible; sequential recommended for bisection).

## Phase 4 — Docs and Cleanup

### Goal

Document the new skill where skills are enumerated, update `CLAUDE_TEMPLATE.md` if it references worktree creation, mark plan complete.

### Work Items

- [ ] 4.1 — **Skill-level registration in `skills/update-zskills/SKILL.md`** (script-level was Phase 1b WI 1b.3). If skills are enumerated by literal name anywhere, add `create-worktree`. If enumerated by glob/loop, no edit needed; phase report documents which.
- [ ] 4.2 — `CLAUDE_TEMPLATE.md`: if it lists worktree-creating skills or describes the creation sequence, reference `scripts/create-worktree.sh` (and `/create-worktree`). Do NOT remove isolation rules. If template lacks such a section, no edit; phase report explains.
- [ ] 4.3 — `plans/PLAN_INDEX.md`: if file exists, add an entry; otherwise skip (`/plans` will rebuild). Disjunctive acceptance.
- [ ] 4.4 — `CHANGELOG.md`: one-line entry mentioning `create-worktree`, in existing style.
- [ ] 4.5 — Frontmatter: `status: complete`.
- [ ] 4.6 — If WI 4.1 modified update-zskills, mirror.

### Acceptance Criteria

- [ ] `grep -c 'create-worktree' skills/update-zskills/SKILL.md` ≥ 1 (or ≥ 2 if WI 4.1 added a skill-level entry; phase report documents).
- [ ] `CLAUDE_TEMPLATE.md` references `create-worktree` OR phase report explains skip.
- [ ] `grep -q 'CREATE_WORKTREE_SKILL' plans/PLAN_INDEX.md` succeeds OR file absent.
- [ ] `CHANGELOG.md` has a new `create-worktree` entry.
- [ ] `head -5 plans/CREATE_WORKTREE_SKILL.md` shows `status: complete`.
- [ ] If WI 4.1 modified update-zskills: `diff -r skills/update-zskills .claude/skills/update-zskills` empty.
- [ ] `bash tests/run-all.sh` exits 0.

### Dependencies

Phases 1a, 1b, 2, 3.

## Drift Log

- **No completed phases — all phases reviewed as remaining.**
- **Plan drafted before `plans/RESTRUCTURE_RUN_PLAN.md` landed (2026-04-19).** Phase 3 file paths updated to reflect post-RESTRUCTURE locations: `/do` worktree-creation lives in `skills/do/modes/pr.md:43` and `skills/do/modes/worktree.md:17,21,23`, NOT `skills/do/SKILL.md`.
- **Phase 2 line numbers drifted ~5 lines** since draft (cherry-pick site `:603` → `:608`; PR site `:814` → `:819`; worktreepurpose instruction `:630-634` → `:635-639`). Re-verified by `grep -n 'git worktree add\|worktree-add-safe\|worktreepurpose' skills/run-plan/SKILL.md`.
- **`/fix-issues` second site (`:1167`) does NOT exist** — only one creation site at `:809`. Original "five sites in fix-issues + do" framing was wrong; the actual five are split as run-plan ×2, fix-issues ×1, do/modes ×2. Overview table updated.
- **`tests/test-hooks.sh` literal-assertion lines drifted** to `:1318` (branch) and `:1328` (path); plan now cites by test name (stable) instead of line number.
- **Update-zskills "three locations" framing was fiction.** The shared-helpers list at `:448-452` is the only edit site; copy/install steps use globs. WI 1b.3 simplified accordingly.

## Plan Review

### Verification Summary (HIGH findings reproduced)

| ID | Claim | Verification command | Evidence | Outcome |
|----|-------|----------------------|----------|---------|
| R-H1 | `/do` worktree code in `do/modes/{pr,worktree}.md`, not SKILL.md | `ls skills/do/modes/`; `grep -rn 'git worktree add\|worktree-add-safe' skills/do/` | `do/modes/pr.md:43`, `do/modes/worktree.md:23` (functional); `do/SKILL.md:437` is doc reference only | Verified |
| R-H2 | RESTRUCTURE_RUN_PLAN is `status: complete` | `head -8 plans/RESTRUCTURE_RUN_PLAN.md` | `status: complete; completed: 2026-04-19` | Verified |
| R-H3 | run-plan line numbers drifted to `:608/:819/:635-639` | `grep -n ... skills/run-plan/SKILL.md` | `:608` git worktree add, `:819` worktree-add-safe, `:635-639` worktreepurpose echo | Verified |
| R-H4 | update-zskills shared-helpers list at `:448-452` | `grep -n 'worktree-add-safe\|sanitize-pipeline-id\|land-phase\|write-landed' skills/update-zskills/SKILL.md` | All four bullets at `:448-452` | Verified |
| R-H5 | Five sites: run-plan ×2, fix-issues ×1, do/modes ×2 (NOT `:1167`) | `grep -rn 'git worktree add\|worktree-add-safe' skills/run-plan skills/do skills/fix-issues` | Exactly 5 functional matches: `run-plan:608`, `run-plan:819`, `fix-issues:809`, `do/modes/pr.md:43`, `do/modes/worktree.md:23` | Verified |

### Disposition Table (all 26 findings)

| ID | Severity | Disposition | Where addressed |
|----|----------|-------------|-----------------|
| R-H1 | HIGH | Fixed | Overview table; Phase 3 WIs 3.2/3.3 paths; WI 3.6 recursive grep |
| R-H2 | HIGH | Fixed | Phase 2 Goal one-sentence coordination note |
| R-H3 | HIGH | Fixed | Phase 2 Goal cites `:608/:819`; WI 2.4 cites `:635-639` |
| R-H4 | HIGH | Fixed | Phase 1b WI 1b.3 collapsed to single edit at `:448-452` |
| R-H5 | HIGH | Fixed | Overview table lists 5 actual sites; `:1167` removed |
| R-M1 | MED | Fixed | Phase 3 WI 3.1 + 3.7 cite test names (stable); line numbers dropped |
| R-M2 | MED (NEW BUG) | Fixed | WI 3.3 inserts `rc=0` before first `create-worktree.sh` invocation |
| R-M3 | MED | Fixed | Phase 1a compressed 319→~140 lines; tables/contracts kept |
| R-M4 | MED | Fixed | Phase 2 WIs 2.1/2.2 are one-sentence specs; bash blocks dropped |
| R-M5 | MED | Fixed | Phase 3 WIs are one-sentence specs (except 3.3 which keeps the rc=0 snippet); fixed `/do` paths |
| R-M6 | MED | Fixed | Cases 1-13 summarized by category; cases 14-20 KEPT verbatim with R-F/R2-* anchors |
| R-M7 | MED | Fixed | Round 1/2 disposition tables deleted; key decisions absorbed into Plan Quality |
| R-M8 | MED | Fixed | Overview compressed 86→~30 lines (paragraph + table + 6 decisions) |
| R-M9 | MED | Fixed | Plan Quality reduced to judgment calls + Round History table |
| R-M10 | MED | Absorbed into R-H4 | — |
| R-L1 | LOW | Fixed | CWD-invariance stated once in Phase 1a §Design; later phases cross-reference |
| R-L2 | LOW | Fixed | WI 3.3 cites `do/modes/worktree.md:17,21` |
| R-L3 | LOW | Fixed | WI 1b.2 says "in the suite block, alphabetical with siblings" |
| R-L4 | LOW | Fixed | Phase 1a Acceptance no longer duplicates slash-rejection cases (covered in Phase 1b 14-20) |
| R-L5 | LOW | Fixed | WI 4.1 acceptance is disjunctive (≥1 or ≥2 with phase-report note) |
| R-L6 | LOW | Fixed | Phase 2/3 verifications use `grep -rcn ... skills/<skill>/` recursively |

### Round History

| Round | Findings | Fixed | Justified | Notes |
|-------|----------|-------|-----------|-------|
| Refine R1 | 26 (5 HIGH / 10 MED / 6 LOW) | 26 | 0 | Full rewrite. Converged in one pass: HIGH fixes are mechanical (path/line updates), compression is large-scale but bounded by anti-cut guidance. |

## Plan Quality

**Five key decisions locked across drafting + refinement:** (1) script-first, slash-command wrapper is thin (R-F1); (2) `--branch-name` decouples branch from path so slashes never enter the filesystem leaf (R2-H1); (3) `--no-preflight` preserves `/do` worktree-mode base-branch semantics (R2-M3); (4) Phase 1 split into 1a/1b for scope (R2-M5); (5) TOCTOU rc=2 remap lives in `create-worktree.sh`, not `worktree-add-safe.sh` (R2-H3).

### Known judgment calls

- `/commit` scoped OUT of creation sites (verified zero `git worktree add`/`worktree-add-safe.sh`).
- Skill wrapper precedent: `worktree-add-safe.sh` and friends ship script-only; this is an experiment in model-driven discoverability.
- `sanitize-pipeline-id.sh` call at `skills/do/modes/pr.md:51` KEPT (defensive; removing requires downstream audit).
- Phase 1a holds at 16 WIs — splitting would ship a script without concurrency safety or rollback.
- `/do` worktree-mode preserves base-branch via `--no-preflight` rather than accepting an ff-merge-from-main shift.
